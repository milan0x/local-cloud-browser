import SwiftUI

struct KinesisFirehosePutRecordView: View {
    @ObservedObject var service: KinesisFirehoseService
    let deliveryStreamName: String
    @Environment(\.dismiss) private var dismiss
    @State private var recordData = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                JSONInputSection(text: $recordData, config: .recordData)
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
        !recordData.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                _ = try await service.putRecord(
                    name: deliveryStreamName,
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
