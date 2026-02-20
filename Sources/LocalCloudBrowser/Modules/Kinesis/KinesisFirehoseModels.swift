import Foundation

enum KinesisTab: String, CaseIterable {
    case streams = "Streams"
    case firehose = "Firehose"
}

struct FirehoseDeliveryStreamSummary: Identifiable, Hashable {
    let deliveryStreamName: String
    let deliveryStreamARN: String
    let deliveryStreamStatus: String
    let deliveryStreamType: String
    let createTimestamp: Date?

    var id: String { deliveryStreamName }

    init(from dict: [String: Any]) {
        deliveryStreamName = dict["DeliveryStreamName"] as? String ?? ""
        deliveryStreamARN = dict["DeliveryStreamARN"] as? String ?? ""
        deliveryStreamStatus = dict["DeliveryStreamStatus"] as? String ?? "ACTIVE"
        deliveryStreamType = dict["DeliveryStreamType"] as? String ?? "DirectPut"
        if let ts = dict["CreateTimestamp"] as? Double {
            createTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            createTimestamp = nil
        }
    }

    init(deliveryStreamName: String = "", deliveryStreamARN: String = "",
         deliveryStreamStatus: String = "ACTIVE", deliveryStreamType: String = "DirectPut",
         createTimestamp: Date? = nil) {
        self.deliveryStreamName = deliveryStreamName
        self.deliveryStreamARN = deliveryStreamARN
        self.deliveryStreamStatus = deliveryStreamStatus
        self.deliveryStreamType = deliveryStreamType
        self.createTimestamp = createTimestamp
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeStreamCLI(endpointUrl: String, region: String) -> String {
        [
            "aws firehose describe-delivery-stream \\",
            "  --delivery-stream-name '\(Self.shellEscape(deliveryStreamName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func deleteStreamCLI(endpointUrl: String, region: String) -> String {
        [
            "aws firehose delete-delivery-stream \\",
            "  --delivery-stream-name '\(Self.shellEscape(deliveryStreamName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listStreamsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws firehose list-delivery-streams \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}

struct FirehoseDeliveryStreamDetail {
    let deliveryStreamName: String
    let deliveryStreamARN: String
    let deliveryStreamStatus: String
    let deliveryStreamType: String
    let versionId: String
    let createTimestamp: Date?
    let lastUpdateTimestamp: Date?
    let destinations: [FirehoseDestination]

    init(from dict: [String: Any]) {
        deliveryStreamName = dict["DeliveryStreamName"] as? String ?? ""
        deliveryStreamARN = dict["DeliveryStreamARN"] as? String ?? ""
        deliveryStreamStatus = dict["DeliveryStreamStatus"] as? String ?? ""
        deliveryStreamType = dict["DeliveryStreamType"] as? String ?? "DirectPut"
        versionId = dict["VersionId"] as? String ?? ""
        if let ts = dict["CreateTimestamp"] as? Double {
            createTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            createTimestamp = nil
        }
        if let ts = dict["LastUpdateTimestamp"] as? Double {
            lastUpdateTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            lastUpdateTimestamp = nil
        }
        if let dests = dict["Destinations"] as? [[String: Any]] {
            destinations = dests.map { FirehoseDestination(from: $0) }
        } else {
            destinations = []
        }
    }
}

struct FirehoseDestination {
    let destinationId: String
    let type: String
    let bucketARN: String?
    let prefix: String?
    let compressionFormat: String?
    let bufferingIntervalInSeconds: Int?
    let bufferingSizeInMBs: Int?
    let roleARN: String?

    init(from dict: [String: Any]) {
        destinationId = dict["DestinationId"] as? String ?? ""

        if let s3 = dict["ExtendedS3DestinationDescription"] as? [String: Any] {
            type = "ExtendedS3"
            bucketARN = s3["BucketARN"] as? String
            prefix = s3["Prefix"] as? String
            compressionFormat = s3["CompressionFormat"] as? String
            roleARN = s3["RoleARN"] as? String
            if let buffering = s3["BufferingHints"] as? [String: Any] {
                bufferingIntervalInSeconds = buffering["IntervalInSeconds"] as? Int
                bufferingSizeInMBs = buffering["SizeInMBs"] as? Int
            } else {
                bufferingIntervalInSeconds = nil
                bufferingSizeInMBs = nil
            }
        } else if let s3 = dict["S3DestinationDescription"] as? [String: Any] {
            type = "S3"
            bucketARN = s3["BucketARN"] as? String
            prefix = s3["Prefix"] as? String
            compressionFormat = s3["CompressionFormat"] as? String
            roleARN = s3["RoleARN"] as? String
            if let buffering = s3["BufferingHints"] as? [String: Any] {
                bufferingIntervalInSeconds = buffering["IntervalInSeconds"] as? Int
                bufferingSizeInMBs = buffering["SizeInMBs"] as? Int
            } else {
                bufferingIntervalInSeconds = nil
                bufferingSizeInMBs = nil
            }
        } else if dict["HttpEndpointDestinationDescription"] != nil {
            type = "HttpEndpoint"
            bucketARN = nil
            prefix = nil
            compressionFormat = nil
            bufferingIntervalInSeconds = nil
            bufferingSizeInMBs = nil
            roleARN = nil
        } else {
            type = "Unknown"
            bucketARN = nil
            prefix = nil
            compressionFormat = nil
            bufferingIntervalInSeconds = nil
            bufferingSizeInMBs = nil
            roleARN = nil
        }
    }
}
