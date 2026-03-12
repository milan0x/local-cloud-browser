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

                Text("Unlimited resource creation across all 28 AWS services.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }
            .padding(.top, 20)

            Spacer().frame(minHeight: 12, maxHeight: 16)

            // MARK: - Context message (e.g. "You've created 3/3 SQS queues")
            if let context = licenseManager.upgradeContext {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(.top, 2)
                    Text(context)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
                .fontWeight(.medium)
                .frame(maxWidth: 300)

                Spacer().frame(height: 12)
            }

            // MARK: - What Pro includes
            VStack(alignment: .leading, spacing: 8) {
                featureRow(icon: "infinity.circle.fill", color: .blue, text: "You will be able to create an unlimited amount of resources")
            }
            .font(.caption)
            .padding(12)
            .frame(maxWidth: 300)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

            Spacer().frame(height: 10)

            // MARK: - Free tier note
            HStack(spacing: 6) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text("Browsing, sending messages, and uploading files is always free.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 300)

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
                    .foregroundStyle(.primary)
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
        .frame(width: 400, height: 530)
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
