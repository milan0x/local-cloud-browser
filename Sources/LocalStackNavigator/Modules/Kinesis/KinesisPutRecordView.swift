import SwiftUI

struct KinesisPutRecordView: View {
    @ObservedObject var service: KinesisService
    let streamName: String
    @Environment(\.dismiss) private var dismiss
    @State private var partitionKey = ""
    @State private var recordData = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Partition Key", text: $partitionKey)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $recordData)
                        .font(.body.monospaced())
                        .frame(minHeight: 120)
                        .border(Color.secondary.opacity(0.3))
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Put Record") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 450)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        !partitionKey.trimmingCharacters(in: .whitespaces).isEmpty &&
        !recordData.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                _ = try await service.putRecord(
                    name: streamName,
                    partitionKey: partitionKey.trimmingCharacters(in: .whitespaces),
                    data: recordData
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
