import Foundation

struct CloudWatchLogGroup: Identifiable, Hashable {
    let logGroupName: String
    let arn: String?
    let creationTime: Date?
    let retentionInDays: Int?
    let storedBytes: Int64

    var id: String { logGroupName }

    var formattedStoredBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: storedBytes)
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeLogGroupsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws logs describe-log-groups \\",
            "  --log-group-name-prefix '\(Self.shellEscape(logGroupName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func describeLogStreamsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws logs describe-log-streams \\",
            "  --log-group-name '\(Self.shellEscape(logGroupName))' \\",
            "  --order-by LastEventTime \\",
            "  --descending \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        logGroupName = dict["logGroupName"] as? String ?? ""
        arn = dict["arn"] as? String
        retentionInDays = dict["retentionInDays"] as? Int
        storedBytes = dict["storedBytes"] as? Int64 ?? 0

        if let ms = dict["creationTime"] as? Double {
            creationTime = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            creationTime = nil
        }
    }
}

struct CloudWatchLogStream: Identifiable, Hashable {
    let logStreamName: String
    let arn: String?
    let creationTime: Date?
    let firstEventTimestamp: Date?
    let lastEventTimestamp: Date?
    let storedBytes: Int64

    var id: String { logStreamName }

    var formattedStoredBytes: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: storedBytes)
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func getLogEventsCLI(logGroupName: String, endpointUrl: String, region: String) -> String {
        [
            "aws logs get-log-events \\",
            "  --log-group-name '\(Self.shellEscape(logGroupName))' \\",
            "  --log-stream-name '\(Self.shellEscape(logStreamName))' \\",
            "  --start-from-head \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        logStreamName = dict["logStreamName"] as? String ?? ""
        arn = dict["arn"] as? String
        storedBytes = dict["storedBytes"] as? Int64 ?? 0

        if let ms = dict["creationTime"] as? Double {
            creationTime = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            creationTime = nil
        }
        if let ms = dict["firstEventTimestamp"] as? Double {
            firstEventTimestamp = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            firstEventTimestamp = nil
        }
        if let ms = dict["lastEventTimestamp"] as? Double {
            lastEventTimestamp = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            lastEventTimestamp = nil
        }
    }
}

struct CloudWatchLogEvent: Identifiable, Hashable {
    let timestamp: Date?
    let message: String
    let ingestionTime: Date?

    var id: String {
        let ts = timestamp.map { String(Int($0.timeIntervalSince1970 * 1000)) } ?? "none"
        return "\(ts)-\(message.hashValue)"
    }

    var isJSON: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    var prettyPrinted: String? {
        guard isJSON,
              let data = message.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    var displayMessage: String {
        prettyPrinted ?? message
    }

    init(from dict: [String: Any]) {
        message = dict["message"] as? String ?? ""

        if let ms = dict["timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            timestamp = nil
        }
        if let ms = dict["ingestionTime"] as? Double {
            ingestionTime = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            ingestionTime = nil
        }
    }
}

struct CloudWatchFilteredLogEvent: Identifiable, Hashable {
    let eventId: String
    let logStreamName: String
    let timestamp: Date?
    let message: String
    let ingestionTime: Date?

    var id: String { eventId }

    var isJSON: Bool {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    var prettyPrinted: String? {
        guard isJSON,
              let data = message.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    var displayMessage: String {
        prettyPrinted ?? message
    }

    init(from dict: [String: Any]) {
        eventId = dict["eventId"] as? String ?? UUID().uuidString
        logStreamName = dict["logStreamName"] as? String ?? ""
        message = dict["message"] as? String ?? ""

        if let ms = dict["timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            timestamp = nil
        }
        if let ms = dict["ingestionTime"] as? Double {
            ingestionTime = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            ingestionTime = nil
        }
    }
}
