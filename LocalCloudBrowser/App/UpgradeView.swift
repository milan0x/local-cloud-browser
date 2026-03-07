import SwiftUI

struct UpgradeView: View {
    @EnvironmentObject private var licenseManager: LicenseManager
    @EnvironmentObject private var storeKitManager: StoreKitManager
    @State private var showRestoreResult = false
    @State private var restoreSuccess = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Unlock Full Access")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create, modify, and manage resources across all 28 AWS services with no restrictions.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)

            if let product = storeKitManager.product {
                Text("\(product.displayPrice) — one-time purchase")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Pay once, own it forever. No subscriptions, no recurring charges.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()

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
                        .padding(.vertical, 8)
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

            Spacer()
        }
        .padding(32)
        .frame(width: 380, height: 360)
        .alert("No Previous Purchase", isPresented: $showRestoreResult) {
            Button("OK") {}
        } message: {
            Text("No previous purchase was found for this Apple ID.")
        }
    }
}
