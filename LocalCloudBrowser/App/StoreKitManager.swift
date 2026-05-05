import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let productID = "localcloudbrowser.unlimited"
    private static let cachedPurchasedKey = "storeKit.cachedIsPurchased"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var isLoading = false
    @Published private(set) var isProductLoading = true

    private var transactionListener: Task<Void, Never>?

    /// Called when purchase state changes so LicenseManager can refresh.
    var onPurchaseChange: (() -> Void)?

    init() {
        // Optimistically trust the last-known-good paid state so a verified
        // paying user doesn't see the "Unlock Unlimited" upgrade UI on every
        // launch while the async entitlement check runs. The server-verified
        // receipt below can still grant access, and an explicit revocation
        // event from Transaction.updates can still revoke it.
        let cached = UserDefaults.standard.bool(forKey: Self.cachedPurchasedKey)
        isPurchased = cached
        Log.info("StoreKitManager init: cachedIsPurchased=\(cached)", category: "StoreKit")
        transactionListener = listenForTransactions()
        Task { await checkEntitlement() }
        Task { await loadProduct() }
    }

    private func setPurchased(_ value: Bool) {
        isPurchased = value
        UserDefaults.standard.set(value, forKey: Self.cachedPurchasedKey)
        // Force flush to disk immediately — SIGKILL (pkill -9) or a crash
        // between a purchase and the next periodic UserDefaults flush would
        // otherwise silently lose the cached purchase state.
        UserDefaults.standard.synchronize()
        Log.info("setPurchased(\(value)) — cache written and synced", category: "StoreKit")
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product

    func loadProduct() async {
        defer { isProductLoading = false }
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            Log.warn("Failed to load StoreKit product: \(error)", category: "StoreKit")
        }
    }

    // MARK: - Purchase

    func purchase() async -> Bool {
        guard let product else {
            Log.warn("No product available to purchase", category: "StoreKit")
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                setPurchased(true)
                onPurchaseChange?()
                Log.info("Purchase successful", category: "StoreKit")
                return true
            case .userCancelled:
                Log.info("Purchase cancelled by user", category: "StoreKit")
                return false
            case .pending:
                Log.info("Purchase pending", category: "StoreKit")
                return false
            @unknown default:
                return false
            }
        } catch {
            Log.warn("Purchase failed: \(error)", category: "StoreKit")
            return false
        }
    }

    // MARK: - Restore

    func restorePurchases() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        try? await AppStore.sync()
        await checkEntitlement()

        if isPurchased {
            onPurchaseChange?()
            Log.info("Purchase restored", category: "StoreKit")
        }
        return isPurchased
    }

    // MARK: - Entitlement

    private func checkEntitlement() async {
        var found = false
        var count = 0
        for await result in Transaction.currentEntitlements {
            count += 1
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.productID,
               transaction.revocationDate == nil {
                found = true
                break
            }
        }
        Log.info("Entitlement check: \(count) entitlement(s), foundPaid=\(found), cached=\(isPurchased)", category: "StoreKit")

        // Entitlement found: confirm the cache.
        if found {
            if !isPurchased {
                setPurchased(true)
                onPurchaseChange?()
            }
            return
        }

        // No entitlement returned. In local StoreKit testing and in transient
        // production lookup failures, this call can return 0 even when the
        // user has paid — we must NOT revoke based on this signal alone, or
        // the cache is useless. Revocation is driven exclusively by explicit
        // refund/revocation events in Transaction.updates (handled below).
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result),
                   transaction.productID == Self.productID {
                    if transaction.revocationDate != nil {
                        Log.info("Transaction revoked (refund/family removal)", category: "StoreKit")
                        self.setPurchased(false)
                    } else {
                        self.setPurchased(true)
                    }
                    self.onPurchaseChange?()
                    await transaction.finish()
                }
            }
        }
    }

    // MARK: - Verification

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value):
            return value
        case .unverified(_, let error):
            throw error
        }
    }
}
