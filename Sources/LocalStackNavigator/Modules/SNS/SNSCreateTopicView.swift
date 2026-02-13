import SwiftUI

struct SNSCreateTopicView: View {
    @ObservedObject var service: SNSService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var topicName = ""
    @State private var isFifo = false
    @State private var serviceError: ServiceError?
    @State private var isCreating = false
    var existingTopicNames: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Topic name", text: $topicName)

                Toggle("FIFO Topic", isOn: $isFifo)

                if isFifo {
                    LabeledContent("Effective name") {
                        Text(effectiveName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if isFifo {
                        Label("FIFO topics guarantee strict message ordering and deduplication.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Standard topics offer best-effort ordering with at-least-once delivery.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A topic named \"\(effectiveName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isCreating)
            }
            .padding()
        }
        .frame(width: 380)
        .serviceErrorAlert(error: $serviceError)
    }

    private var effectiveName: String {
        let trimmed = topicName.trimmingCharacters(in: .whitespaces)
        if isFifo && !trimmed.hasSuffix(".fifo") {
            return trimmed + ".fifo"
        }
        return trimmed
    }

    private var nameExists: Bool {
        let name = effectiveName
        return !name.isEmpty && existingTopicNames.contains(name)
    }

    private var isValid: Bool {
        let name = effectiveName
        guard !name.isEmpty else { return false }
        let baseName = isFifo ? String(name.dropLast(5)) : name
        guard baseName.count >= 1, baseName.count <= 256 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return baseName.unicodeScalars.allSatisfy { allowed.contains($0) } && !nameExists
    }

    private func create() {
        isCreating = true
        serviceError = nil
        Task {
            do {
                _ = try await service.createTopic(name: effectiveName, isFifo: isFifo)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isCreating = false
            }
        }
    }
}
