import SwiftUI

struct KinesisCreateStreamView: View {
    @ObservedObject var service: KinesisService
    @Environment(\.dismiss) private var dismiss
    @State private var streamName = ""
    @State private var shardCount = 1
    @State private var streamMode = "PROVISIONED"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private let streamModes = ["PROVISIONED", "ON_DEMAND"]

    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        CreateFormScaffold(
            width: 420,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Stream Name", text: $streamName)

                Picker("Stream Mode", selection: $streamMode) {
                    ForEach(streamModes, id: \.self) { mode in
                        Text(mode).tag(mode)
                    }
                }

                if streamMode == "PROVISIONED" {
                    Stepper("Shard Count: \(shardCount)", value: $shardCount, in: 1...100)
                }
        }
    }

    private var isValid: Bool {
        !streamName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createStream(
                    name: streamName.trimmingCharacters(in: .whitespaces),
                    shardCount: shardCount,
                    mode: streamMode
                )
                onCreate?(streamName.trimmingCharacters(in: .whitespaces))
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
