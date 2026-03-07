import SwiftUI

struct UpgradeView: View {
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var storeKitManager: StoreKitManager
    @State private var showRestoreResult = false
    @State private var restoreSuccess = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            VStack(spacing: 12) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                Text("Unlock Full Access")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Create, modify, and manage resources across all 28 AWS services with no restrictions.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }
            .padding(.top, 32)

            Spacer().frame(minHeight: 16, maxHeight: 24)

            // MARK: - Trial status
            if !licenseManager.isPaid {
                let days = licenseManager.trialDaysRemaining
                HStack(spacing: 6) {
                    Image(systemName: days > 0 ? "clock" : "exclamationmark.triangle.fill")
                        .foregroundStyle(days > 0 ? .orange : .red)
                    Text(days > 0
                         ? "\(days) \(days == 1 ? "day" : "days") remaining in your trial"
                         : "Your trial has expired")
                }
                .font(.callout)
                .fontWeight(.medium)

                Spacer().frame(height: 12)
            }

            // MARK: - Free tier info
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.system(size: 14))
                    .padding(.top, 1)
                Text("Browsing, sending messages, uploading files, and interacting with existing resources is always free")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .padding(12)
            .frame(maxWidth: 300)
            .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

            Spacer().frame(minHeight: 16, maxHeight: 24)

            // MARK: - Price
            VStack(spacing: 4) {
                if let product = storeKitManager.product {
                    Text("\(product.displayPrice) — one-time purchase")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Text("Pay once, own it forever. No subscriptions.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer().frame(minHeight: 20, maxHeight: 28)

            // MARK: - Actions
            VStack(spacing: 10) {
                Button {
                    Task {
                        let success = await storeKitManager.purchase()
                        if success { dismiss() }
                    }
                } label: {
                    Text("Purchase")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(storeKitManager.isLoading)
                .opacity(storeKitManager.isLoading ? 0.5 : 1)

                Button {
                    Task {
                        restoreSuccess = await storeKitManager.restorePurchases()
                        if restoreSuccess {
                            dismiss()
                        } else {
                            showRestoreResult = true
                        }
                    }
                } label: {
                    Text("Restore Purchase")
                        .font(.callout)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .disabled(storeKitManager.isLoading)

                Button("Not Now") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
            .padding(.bottom, 28)
        }
        .padding(.horizontal, 36)
        .frame(width: 400, height: 500)
        .alert("No Previous Purchase", isPresented: $showRestoreResult) {
            Button("OK") {}
        } message: {
            Text("No previous purchase was found for this Apple ID.")
        }
    }
}
