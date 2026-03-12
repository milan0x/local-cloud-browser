import SwiftUI

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)

                Text("Welcome to Local Cloud Browser")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Browse and manage your cloud services with a native macOS experience.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
            }
            .padding(.top, 28)

            Spacer().frame(height: 24)

            VStack(alignment: .leading, spacing: 12) {
                Text("What's included for free")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 2)

                featureRow(
                    icon: "eye",
                    color: .blue,
                    title: "Browse & Explore",
                    subtitle: "View all your resources across 28 AWS services"
                )
                featureRow(
                    icon: "paperplane",
                    color: .green,
                    title: "Send & Upload",
                    subtitle: "Push messages, upload files, and interact with your resources"
                )
                featureRow(
                    icon: "plus.circle",
                    color: .orange,
                    title: "Create Resources",
                    subtitle: "Create up to 3 resources per service"
                )
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            Button {
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 420)
    }

    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
