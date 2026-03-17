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
        CreateFormScaffold(
            width: 450,
            isValid: isValid,
            isCreating: isSaving,
            createLabel: "Put Record",
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Partition Key", text: $partitionKey)

                JSONInputSection(text: $recordData, config: .recordData)
        }
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
