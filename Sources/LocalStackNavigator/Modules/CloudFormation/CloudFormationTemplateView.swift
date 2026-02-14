import SwiftUI
import AppKit

struct CloudFormationTemplateView: View {
    @ObservedObject var service: CloudFormationService
    let stackName: String
    @Environment(\.dismiss) private var dismiss

    @State private var templateBody = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Template — \(stackName)")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if isLoading {
                ProgressView("Loading template...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(errorMessage)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CodeTextEditor(text: .constant(templateBody), isEditable: false)
            }

            Divider()

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(templateBody, forType: .string)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 700)
        .frame(minHeight: 500)
        .task { loadTemplate() }
    }

    private func loadTemplate() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                var body = try await service.getTemplate(name: stackName)
                // Pretty-print JSON templates
                if let data = body.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
                   let result = String(data: pretty, encoding: .utf8) {
                    body = result
                }
                templateBody = body
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}
