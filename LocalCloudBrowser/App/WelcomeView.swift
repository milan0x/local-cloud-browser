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
                featureRow(
                    icon: "eye",
                    color: .blue,
                    title: "Browse Your Services",
                    subtitle: "S3, SQS, DynamoDB, and 25 more — on LocalStack, MinIO, or AWS"
                )
                featureRow(
                    icon: "lock.fill",
                    color: .orange,
                    title: "Safe by Default",
                    subtitle: "Read-only mode blocks writes until you unlock it from the toolbar"
                )
                featureRow(
                    icon: "paperplane",
                    color: .green,
                    title: "Create & Interact",
                    subtitle: "Send messages, upload files, and create resources"
                )
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 24)

            Button {
                dismiss()
            } label: {
                Text("Get Started")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
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
