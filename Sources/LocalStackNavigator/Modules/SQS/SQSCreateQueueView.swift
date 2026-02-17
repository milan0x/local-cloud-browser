import SwiftUI

struct SQSCreateQueueView: View {
    @ObservedObject var service: SQSService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var queueName = ""
    @State private var isFifo = false
    @State private var serviceError: ServiceError?
    @State private var isCreating = false
    var existingQueueNames: Set<String>

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Queue name", text: $queueName)

                Toggle("FIFO Queue", isOn: $isFifo)

                if isFifo {
                    LabeledContent("Effective name") {
                        Text(effectiveName)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if isFifo {
                        Label("FIFO queues guarantee exactly-once processing and message ordering.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Standard queues offer maximum throughput with best-effort ordering.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A queue named \"\(effectiveName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()
                .padding(.top, 8)

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
        let trimmed = queueName.trimmingCharacters(in: .whitespaces)
        if isFifo && !trimmed.hasSuffix(".fifo") {
            return trimmed + ".fifo"
        }
        return trimmed
    }

    private var nameExists: Bool {
        let name = effectiveName
        return !name.isEmpty && existingQueueNames.contains(name)
    }

    private var isValid: Bool {
        let name = effectiveName
        guard !name.isEmpty else { return false }
        let baseName = isFifo ? String(name.dropLast(5)) : name // remove .fifo for length check
        guard baseName.count >= 1, baseName.count <= 80 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return baseName.unicodeScalars.allSatisfy { allowed.contains($0) } && !nameExists
    }

    private func create() {
        isCreating = true
        serviceError = nil
        Task {
            do {
                _ = try await service.createQueue(name: effectiveName, isFifo: isFifo)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isCreating = false
            }
        }
    }
}
