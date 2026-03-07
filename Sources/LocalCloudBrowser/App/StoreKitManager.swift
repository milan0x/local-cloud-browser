import StoreKit

@MainActor
final class StoreKitManager: ObservableObject {
    static let productID = "com.localcloudbrowser.pro"

    @Published private(set) var product: Product?
    @Published private(set) var isPurchased = false
    @Published private(set) var isLoading = false

    private var transactionListener: Task<Void, Never>?

    /// Called when purchase state changes so LicenseManager can refresh.
    var onPurchaseChange: (() -> Void)?

    init() {
        transactionListener = listenForTransactions()
        Task { await checkEntitlement() }
        Task { await loadProduct() }
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Product

    func loadProduct() async {
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
                isPurchased = true
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
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               transaction.productID == Self.productID {
                isPurchased = true
                onPurchaseChange?()
                return
            }
        }
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                if let transaction = try? self.checkVerified(result),
                   transaction.productID == Self.productID {
                    self.isPurchased = true
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
