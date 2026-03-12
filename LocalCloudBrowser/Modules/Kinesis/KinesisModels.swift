import Foundation

struct KinesisStreamSummary: Identifiable, Hashable {
    let streamName: String
    let streamARN: String
    let streamStatus: String
    let streamMode: String
    let creationTimestamp: Date?

    var id: String { streamName }

    var statusBadgeColor: String {
        switch streamStatus {
        case "ACTIVE": return "green"
        case "CREATING": return "orange"
        case "DELETING": return "red"
        case "UPDATING": return "blue"
        default: return "gray"
        }
    }

    init(streamName: String = "", streamARN: String = "", streamStatus: String = "ACTIVE",
         streamMode: String = "PROVISIONED", creationTimestamp: Date? = nil) {
        self.streamName = streamName
        self.streamARN = streamARN
        self.streamStatus = streamStatus
        self.streamMode = streamMode
        self.creationTimestamp = creationTimestamp
    }

    init(from dict: [String: Any]) {
        streamName = dict["StreamName"] as? String ?? ""
        streamARN = dict["StreamARN"] as? String ?? ""
        streamStatus = dict["StreamStatus"] as? String ?? "ACTIVE"
        if let modeDetails = dict["StreamModeDetails"] as? [String: Any] {
            streamMode = modeDetails["StreamMode"] as? String ?? "PROVISIONED"
        } else {
            streamMode = "PROVISIONED"
        }
        if let ts = dict["StreamCreationTimestamp"] as? Double {
            creationTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            creationTimestamp = nil
        }
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeStreamCLI(endpointUrl: String, region: String) -> String {
        [
            "aws kinesis describe-stream-summary \\",
            "  --stream-name '\(Self.shellEscape(streamName))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    func deleteStreamCLI(endpointUrl: String, region: String) -> String {
        [
            "aws kinesis delete-stream \\",
            "  --stream-name '\(Self.shellEscape(streamName))' \\",
            "  --enforce-consumer-deletion \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listStreamsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws kinesis list-streams \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct KinesisStreamDetail {
    let streamName: String
    let streamARN: String
    let streamStatus: String
    let streamMode: String
    let retentionPeriodHours: Int
    let openShardCount: Int
    let encryptionType: String
    let keyId: String?
    let creationTimestamp: Date?

    init(from dict: [String: Any]) {
        streamName = dict["StreamName"] as? String ?? ""
        streamARN = dict["StreamARN"] as? String ?? ""
        streamStatus = dict["StreamStatus"] as? String ?? ""
        if let modeDetails = dict["StreamModeDetails"] as? [String: Any] {
            streamMode = modeDetails["StreamMode"] as? String ?? "PROVISIONED"
        } else {
            streamMode = "PROVISIONED"
        }
        retentionPeriodHours = dict["RetentionPeriodHours"] as? Int ?? 24
        openShardCount = dict["OpenShardCount"] as? Int ?? 0
        encryptionType = dict["EncryptionType"] as? String ?? "NONE"
        keyId = dict["KeyId"] as? String
        if let ts = dict["StreamCreationTimestamp"] as? Double {
            creationTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            creationTimestamp = nil
        }
    }
}

struct KinesisShard: Identifiable {
    let shardId: String
    let parentShardId: String?
    let hashKeyRange: HashKeyRange
    let sequenceNumberRange: KinesisSequenceNumberRange

    var id: String { shardId }

    var truncatedId: String {
        if shardId.count > 24 {
            return "..." + String(shardId.suffix(20))
        }
        return shardId
    }

    var isClosed: Bool {
        sequenceNumberRange.endingSequenceNumber != nil
    }

    init(from dict: [String: Any]) {
        shardId = dict["ShardId"] as? String ?? ""
        parentShardId = dict["ParentShardId"] as? String
        if let range = dict["HashKeyRange"] as? [String: Any] {
            hashKeyRange = HashKeyRange(from: range)
        } else {
            hashKeyRange = HashKeyRange(startingHashKey: nil, endingHashKey: nil)
        }
        if let range = dict["SequenceNumberRange"] as? [String: Any] {
            sequenceNumberRange = KinesisSequenceNumberRange(from: range)
        } else {
            sequenceNumberRange = KinesisSequenceNumberRange(startingSequenceNumber: nil, endingSequenceNumber: nil)
        }
    }
}

struct HashKeyRange {
    let startingHashKey: String?
    let endingHashKey: String?

    init(from dict: [String: Any]) {
        startingHashKey = dict["StartingHashKey"] as? String
        endingHashKey = dict["EndingHashKey"] as? String
    }

    init(startingHashKey: String?, endingHashKey: String?) {
        self.startingHashKey = startingHashKey
        self.endingHashKey = endingHashKey
    }
}

struct KinesisSequenceNumberRange {
    let startingSequenceNumber: String?
    let endingSequenceNumber: String?

    init(from dict: [String: Any]) {
        startingSequenceNumber = dict["StartingSequenceNumber"] as? String
        endingSequenceNumber = dict["EndingSequenceNumber"] as? String
    }

    init(startingSequenceNumber: String?, endingSequenceNumber: String?) {
        self.startingSequenceNumber = startingSequenceNumber
        self.endingSequenceNumber = endingSequenceNumber
    }
}

struct KinesisRecord: Identifiable {
    let sequenceNumber: String
    let partitionKey: String
    let data: String
    let approximateArrivalTimestamp: Date?

    var id: String { sequenceNumber }

    var decodedData: String {
        guard let decoded = Data(base64Encoded: data),
              let text = String(data: decoded, encoding: .utf8) else {
            return data
        }
        return text
    }

    var isJSON: Bool {
        guard let decoded = Data(base64Encoded: data),
              let text = String(data: decoded, encoding: .utf8),
              let textData = text.data(using: .utf8) else {
            return false
        }
        return (try? JSONSerialization.jsonObject(with: textData)) != nil
    }

    var prettyJSON: String? {
        guard let decoded = Data(base64Encoded: data),
              let text = String(data: decoded, encoding: .utf8),
              let textData = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: textData),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    init(from dict: [String: Any]) {
        sequenceNumber = dict["SequenceNumber"] as? String ?? ""
        partitionKey = dict["PartitionKey"] as? String ?? ""
        data = dict["Data"] as? String ?? ""
        if let ts = dict["ApproximateArrivalTimestamp"] as? Double {
            approximateArrivalTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            approximateArrivalTimestamp = nil
        }
    }
}
