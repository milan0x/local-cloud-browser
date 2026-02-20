import SwiftUI

struct ConfigDeliveryChannelDetailView: View {
    let channel: DeliveryChannel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                channelInfoSection
            }
            .padding(16)
        }
    }

    private var channelInfoSection: some View {
        GroupBox("Channel Information") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Name") {
                    CopyableValue(text: channel.name, monospaced: true)
                }
                labeledRow("S3 Bucket") {
                    CopyableValue(text: channel.s3BucketName, monospaced: true)
                }
                if !channel.s3KeyPrefix.isEmpty {
                    labeledRow("S3 Key Prefix") {
                        CopyableValue(text: channel.s3KeyPrefix, monospaced: true)
                    }
                }
                if !channel.snsTopicARN.isEmpty {
                    labeledRow("SNS Topic") {
                        CopyableValue(text: channel.snsTopicARN, font: .caption, monospaced: true)
                    }
                }
                if !channel.deliveryFrequency.isEmpty {
                    labeledRow("Frequency") {
                        Text(channel.deliveryFrequency)
                            .font(.body.monospaced())
                    }
                }
            }
            .padding(4)
        }
    }

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
        }
    }
}
