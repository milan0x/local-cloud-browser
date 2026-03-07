import SwiftUI
import AppKit

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    enum Category: String, CaseIterable {
        case bug = "Bug Report"
        case feature = "Feature Request"
        case general = "General Feedback"
    }

    @State private var category: Category = .general
    @State private var message = ""

    private var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private var appVersion: String { AppInfo.version }

    private var formattedFeedback: String {
        """
        [\(category.rawValue)]

        \(message)

        ---
        App: Local Cloud Browser \(appVersion)
        macOS: \(macOSVersion)
        """
    }

    private static let feedbackEmail = AppInfo.contactEmail

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Send Feedback")
                .font(.title2)
                .fontWeight(.semibold)

            Picker("Category", selection: $category) {
                ForEach(Category.allCases, id: \.self) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.segmented)

            TextEditor(text: $message)
                .font(.body)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3))

            GroupBox("System Info") {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("App", value: "Local Cloud Browser \(appVersion)")
                    LabeledContent("macOS", value: macOSVersion)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button("Copy to Clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(formattedFeedback, forType: .string)
                    dismiss()
                }

                Button("Compose Email...") {
                    openMailto()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func openMailto() {
        let subject = "[\(category.rawValue)] Local Cloud Browser Feedback"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Self.feedbackEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: formattedFeedback),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
}
