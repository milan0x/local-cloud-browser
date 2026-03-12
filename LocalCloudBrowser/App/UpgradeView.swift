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

                Text("Unlimited resource creation, auto-refresh, and more across all 28 AWS services.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }
            .padding(.top, 20)

            Spacer().frame(minHeight: 12, maxHeight: 16)

            // MARK: - Context message (e.g. "You've created 3/3 SQS queues")
            if let context = licenseManager.upgradeContext {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(context)
                }
                .font(.callout)
                .fontWeight(.medium)

                Spacer().frame(height: 12)
            }

            // MARK: - Feature comparison
            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "checkmark.circle.fill", color: .green, text: "Browse, send messages, upload files — always free")
                featureRow(icon: "3.circle.fill", color: .orange, text: "3 resource creates per service on Free")
                featureRow(icon: "infinity.circle.fill", color: .blue, text: "Unlimited creates with Pro")
            }
            .font(.caption)
            .padding(12)
            .frame(maxWidth: 300)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

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
                .accessibilityLabel("Purchase")

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
                .accessibilityLabel("Restore Purchase")

                Button("Not Now") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.callout)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 36)
        .frame(width: 400, height: 480)
        .onDisappear {
            licenseManager.upgradeContext = nil
        }
        .alert("No Previous Purchase", isPresented: $showRestoreResult) {
            Button("OK") {}
        } message: {
            Text("No previous purchase was found for this Apple ID.")
        }
    }

    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.system(size: 14))
                .padding(.top, 1)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
