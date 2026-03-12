import Foundation

enum ConfigTab: String, CaseIterable {
    case recorders = "Recorders"
    case deliveryChannels = "Delivery Channels"
}

struct ConfigurationRecorder: Identifiable, Hashable {
    let name: String
    let roleARN: String
    let allSupported: Bool
    let resourceTypes: [String]

    var id: String { name }

    init(from dict: [String: Any]) {
        name = dict["name"] as? String ?? ""
        roleARN = dict["roleARN"] as? String ?? ""
        if let group = dict["recordingGroup"] as? [String: Any] {
            allSupported = group["allSupported"] as? Bool ?? true
            resourceTypes = group["resourceTypes"] as? [String] ?? []
        } else {
            allSupported = true
            resourceTypes = []
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: ConfigurationRecorder, rhs: ConfigurationRecorder) -> Bool {
        lhs.name == rhs.name && lhs.roleARN == rhs.roleARN &&
        lhs.allSupported == rhs.allSupported && lhs.resourceTypes == rhs.resourceTypes
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeRecorderCLI(endpointUrl: String, region: String) -> String {
        [
            "aws configservice describe-configuration-recorders \\",
            "  --configuration-recorder-names '\(Self.shellEscape(name))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listRecordersCLI(endpointUrl: String, region: String) -> String {
        [
            "aws configservice describe-configuration-recorders \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct ConfigurationRecorderStatus {
    let name: String
    let recording: Bool
    let lastStartTime: Date?
    let lastStopTime: Date?
    let lastStatus: String
    let lastStatusChangeTime: Date?

    init(from dict: [String: Any]) {
        name = dict["name"] as? String ?? ""
        recording = dict["recording"] as? Bool ?? false
        lastStatus = dict["lastStatus"] as? String ?? ""
        if let ts = dict["lastStartTime"] as? Double {
            lastStartTime = Date(timeIntervalSince1970: ts)
        } else {
            lastStartTime = nil
        }
        if let ts = dict["lastStopTime"] as? Double {
            lastStopTime = Date(timeIntervalSince1970: ts)
        } else {
            lastStopTime = nil
        }
        if let ts = dict["lastStatusChangeTime"] as? Double {
            lastStatusChangeTime = Date(timeIntervalSince1970: ts)
        } else {
            lastStatusChangeTime = nil
        }
    }
}

struct DeliveryChannel: Identifiable, Hashable {
    let name: String
    let s3BucketName: String
    let s3KeyPrefix: String
    let snsTopicARN: String
    let deliveryFrequency: String

    var id: String { name }

    init(from dict: [String: Any]) {
        name = dict["name"] as? String ?? ""
        s3BucketName = dict["s3BucketName"] as? String ?? ""
        s3KeyPrefix = dict["s3KeyPrefix"] as? String ?? ""
        snsTopicARN = dict["snsTopicARN"] as? String ?? ""
        if let freq = dict["configSnapshotDeliveryProperties"] as? [String: Any] {
            deliveryFrequency = freq["deliveryFrequency"] as? String ?? ""
        } else {
            deliveryFrequency = ""
        }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }

    static func == (lhs: DeliveryChannel, rhs: DeliveryChannel) -> Bool {
        lhs.name == rhs.name && lhs.s3BucketName == rhs.s3BucketName &&
        lhs.s3KeyPrefix == rhs.s3KeyPrefix && lhs.snsTopicARN == rhs.snsTopicARN &&
        lhs.deliveryFrequency == rhs.deliveryFrequency
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeChannelCLI(endpointUrl: String, region: String) -> String {
        [
            "aws configservice describe-delivery-channels \\",
            "  --delivery-channel-names '\(Self.shellEscape(name))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listChannelsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws configservice describe-delivery-channels \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}
