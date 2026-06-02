import SwiftUI

struct ConfigCreateDeliveryChannelView: View {
    @ObservedObject var service: ConfigService
    var onCreate: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var s3BucketName = ""
    @State private var s3KeyPrefix = ""
    @State private var snsTopicARN = ""
    @State private var deliveryFrequency = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false

    private let frequencies = ["", "One_Hour", "Three_Hours", "Six_Hours", "Twelve_Hours", "TwentyFour_Hours"]

    var body: some View {
        CreateFormScaffold(
            width: 420,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Channel Name", text: $name)
                TextField("S3 Bucket Name", text: $s3BucketName)
                TextField("S3 Key Prefix (optional)", text: $s3KeyPrefix)
                TextField("SNS Topic ARN (optional)", text: $snsTopicARN)
                Picker("Delivery Frequency", selection: $deliveryFrequency) {
                    Text("None").tag("")
                    ForEach(frequencies.dropFirst(), id: \.self) { freq in
                        Text(freq.replacingOccurrences(of: "_", with: " ")).tag(freq)
                    }
                }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !s3BucketName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let channelName = name.trimmingCharacters(in: .whitespaces)
                try await service.putDeliveryChannel(
                    name: channelName,
                    s3BucketName: s3BucketName.trimmingCharacters(in: .whitespaces),
                    s3KeyPrefix: s3KeyPrefix.trimmingCharacters(in: .whitespaces),
                    snsTopicARN: snsTopicARN.trimmingCharacters(in: .whitespaces),
                    frequency: deliveryFrequency
                )
                onCreate?(channelName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
