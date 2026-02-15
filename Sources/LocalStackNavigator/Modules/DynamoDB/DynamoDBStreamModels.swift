import Foundation
import SwiftUI

// MARK: - Stream Models

struct DynamoDBStream: Identifiable {
    let streamArn: String
    let streamLabel: String
    let tableName: String

    var id: String { streamArn }

    init(from dict: [String: Any]) {
        streamArn = dict["StreamArn"] as? String ?? ""
        streamLabel = dict["StreamLabel"] as? String ?? ""
        tableName = dict["TableName"] as? String ?? ""
    }
}

struct DynamoDBStreamDescription {
    let streamArn: String
    let streamLabel: String
    let streamStatus: String
    let streamViewType: String
    let tableName: String
    let keySchema: [KeySchemaElement]
    let shards: [DynamoDBShard]

    init(from dict: [String: Any]) {
        streamArn = dict["StreamArn"] as? String ?? ""
        streamLabel = dict["StreamLabel"] as? String ?? ""
        streamStatus = dict["StreamStatus"] as? String ?? ""
        streamViewType = dict["StreamViewType"] as? String ?? ""
        tableName = dict["TableName"] as? String ?? ""
        keySchema = (dict["KeySchema"] as? [[String: Any]] ?? []).map { KeySchemaElement(from: $0) }
        shards = (dict["Shards"] as? [[String: Any]] ?? []).map { DynamoDBShard(from: $0) }
    }
}

struct DynamoDBShard: Identifiable {
    let shardId: String
    let parentShardId: String?
    let sequenceNumberRange: SequenceNumberRange

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
        if let range = dict["SequenceNumberRange"] as? [String: Any] {
            sequenceNumberRange = SequenceNumberRange(from: range)
        } else {
            sequenceNumberRange = SequenceNumberRange(startingSequenceNumber: nil, endingSequenceNumber: nil)
        }
    }
}

struct SequenceNumberRange {
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

// MARK: - Stream Record

struct DynamoDBStreamRecord: Identifiable {
    let eventID: String
    let eventName: String // INSERT, MODIFY, REMOVE
    let approximateCreationDateTime: Date?
    let keys: [String: AttributeValue]
    let newImage: [String: AttributeValue]?
    let oldImage: [String: AttributeValue]?
    let sequenceNumber: String
    let sizeBytes: Int

    var id: String { eventID }

    var eventColor: Color {
        switch eventName {
        case "INSERT": return .green
        case "MODIFY": return .blue
        case "REMOVE": return .red
        default: return .secondary
        }
    }

    var keySummary: String {
        keys.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)=\($0.value.displayString)" }
            .joined(separator: ", ")
    }

    init(from dict: [String: Any]) {
        eventID = dict["eventID"] as? String ?? ""
        eventName = dict["eventName"] as? String ?? ""
        sequenceNumber = dict["dynamodb"].flatMap { ($0 as? [String: Any])?["SequenceNumber"] as? String } ?? ""
        sizeBytes = dict["dynamodb"].flatMap { ($0 as? [String: Any])?["SizeBytes"] as? Int } ?? 0

        if let ts = dict["dynamodb"].flatMap({ ($0 as? [String: Any])?["ApproximateCreationDateTime"] }) {
            if let epoch = ts as? Double {
                approximateCreationDateTime = Date(timeIntervalSince1970: epoch)
            } else if let epoch = ts as? Int {
                approximateCreationDateTime = Date(timeIntervalSince1970: Double(epoch))
            } else {
                approximateCreationDateTime = nil
            }
        } else {
            approximateCreationDateTime = nil
        }

        let dynamodb = dict["dynamodb"] as? [String: Any] ?? [:]

        if let keysDict = dynamodb["Keys"] as? [String: Any] {
            var parsed: [String: AttributeValue] = [:]
            for (k, v) in keysDict {
                if let vDict = v as? [String: Any], let av = AttributeValue.fromJSON(vDict) {
                    parsed[k] = av
                }
            }
            keys = parsed
        } else {
            keys = [:]
        }

        if let newDict = dynamodb["NewImage"] as? [String: Any] {
            var parsed: [String: AttributeValue] = [:]
            for (k, v) in newDict {
                if let vDict = v as? [String: Any], let av = AttributeValue.fromJSON(vDict) {
                    parsed[k] = av
                }
            }
            newImage = parsed
        } else {
            newImage = nil
        }

        if let oldDict = dynamodb["OldImage"] as? [String: Any] {
            var parsed: [String: AttributeValue] = [:]
            for (k, v) in oldDict {
                if let vDict = v as? [String: Any], let av = AttributeValue.fromJSON(vDict) {
                    parsed[k] = av
                }
            }
            oldImage = parsed
        } else {
            oldImage = nil
        }
    }
}
