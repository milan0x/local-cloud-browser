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
    var onCreate: ((String, String) -> Void)? = nil

    var body: some View {
        CreateFormScaffold(
            isValid: isValid,
            isCreating: isCreating,
            serviceError: $serviceError,
            onCreate: create
        ) {
            TextField("Queue name", text: $queueName)
                .onChange(of: queueName) { _, new in
                    // SQS queue names don't allow whitespace (only
                    // alphanumerics + `-` `_`). Rather than silently
                    // disabling the Create button when the user hits
                    // space, strip the invalid character on input so
                    // the field stays valid and the user gets the
                    // feedback immediately.
                    let stripped = new.filter { !$0.isWhitespace }
                    if stripped != new { queueName = stripped }
                }

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

            if nameExists {
                Text("A queue named \"\(effectiveName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
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
                let url = try await service.createQueue(name: effectiveName, isFifo: isFifo)
                onCreate?(effectiveName, url)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isCreating = false
            }
        }
    }
}
