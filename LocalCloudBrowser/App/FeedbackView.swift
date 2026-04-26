import SwiftUI
import AppKit

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""

    private let appVersion: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }()

    private var macOSVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Local Cloud Browser Feedback")
                    .font(.headline)
                Text("Your feedback will be sent via your email client.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $feedbackText)
                    .font(.body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.quaternary)
                    )

                Text("Local Cloud Browser \(appVersion) · macOS \(macOSVersion)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Send with Email") { sendFeedback() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 420)
    }

    private func sendFeedback() {
        let subject = "Local Cloud Browser Feedback"
        // Message FIRST so the email client's cursor lands above the
        // version footer when the user wants to add more after the
        // composer opens. The footer is short and unobtrusive at the
        // tail end where it doesn't get in the way of the conversation.
        let body = feedbackText + "\n\n---\nLocal Cloud Browser \(appVersion) · macOS \(macOSVersion)"
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:\(AppInfo.contactEmail)?subject=\(encodedSubject)&body=\(encodedBody)") {
            NSWorkspace.shared.open(url)
        }
        dismiss()
    }
}
