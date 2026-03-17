import SwiftUI

struct KinesisFirehosePutRecordView: View {
    @ObservedObject var service: KinesisFirehoseService
    let deliveryStreamName: String
    @Environment(\.dismiss) private var dismiss
    @State private var recordData = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    var body: some View {
        CreateFormScaffold(
            width: 450,
            isValid: isValid,
            isCreating: isSaving,
            createLabel: "Put Record",
            serviceError: $serviceError,
            onCreate: save
        ) {
                JSONInputSection(text: $recordData, config: .recordData)
        }
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
