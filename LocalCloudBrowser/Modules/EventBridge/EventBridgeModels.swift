import Foundation

struct EventBridgeBus: Identifiable, Hashable {
    let name: String
    let arn: String?
    let description: String?
    let creationTime: Date?
    let lastModifiedTime: Date?

    var id: String { name }

    var isDefault: Bool { name == "default" }

    func listRulesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws events list-rules \\",
            "  --event-bus-name '\(name.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        name = dict["Name"] as? String ?? ""
        arn = dict["Arn"] as? String
        description = dict["Description"] as? String

        if let ts = dict["CreationTime"] as? Double {
            creationTime = Date(timeIntervalSince1970: ts)
        } else {
            creationTime = nil
        }
        if let ts = dict["LastModifiedTime"] as? Double {
            lastModifiedTime = Date(timeIntervalSince1970: ts)
        } else {
            lastModifiedTime = nil
        }
    }
}

struct EventBridgeRule: Identifiable, Hashable {
    let name: String
    let arn: String?
    let eventPattern: String?
    let scheduleExpression: String?
    let state: String
    let description: String?
    let eventBusName: String?
    let roleArn: String?
    let managedBy: String?

    var id: String { name }

    var isEnabled: Bool { state == "ENABLED" }

    enum RuleType {
        case eventPattern
        case schedule
        case unknown

        var displayName: String {
            switch self {
            case .eventPattern: "Event Pattern"
            case .schedule: "Schedule"
            case .unknown: "Unknown"
            }
        }

        var systemImage: String {
            switch self {
            case .eventPattern: "curlybraces"
            case .schedule: "clock"
            case .unknown: "questionmark.circle"
            }
        }
    }

    var ruleType: RuleType {
        if eventPattern != nil { return .eventPattern }
        if scheduleExpression != nil { return .schedule }
        return .unknown
    }

    var prettyEventPattern: String? {
        guard let pattern = eventPattern,
              let data = pattern.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return eventPattern
        }
        return result
    }

    func describeRuleCLI(endpointUrl: String, region: String) -> String {
        var parts = [
            "aws events describe-rule \\",
            "  --name '\(name.shellEscaped())' \\",
        ]
        if let bus = eventBusName {
            parts.append("  --event-bus-name '\(bus.shellEscaped())' \\")
        }
        parts.append("  --endpoint-url '\(endpointUrl)' \\")
        parts.append("  --region '\(region)'")
        return parts.joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        name = dict["Name"] as? String ?? ""
        arn = dict["Arn"] as? String
        eventPattern = dict["EventPattern"] as? String
        scheduleExpression = dict["ScheduleExpression"] as? String
        state = dict["State"] as? String ?? "ENABLED"
        description = dict["Description"] as? String
        eventBusName = dict["EventBusName"] as? String
        roleArn = dict["RoleArn"] as? String
        managedBy = dict["ManagedBy"] as? String
    }
}

struct EventBridgeTarget: Identifiable, Hashable {
    let targetId: String
    let arn: String
    let roleArn: String?
    let input: String?
    let inputPath: String?
    let deadLetterArn: String?

    var id: String { targetId }

    var prettyInput: String? {
        guard let inp = input,
              let data = inp.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return input
        }
        return result
    }

    init(from dict: [String: Any]) {
        targetId = dict["Id"] as? String ?? ""
        arn = dict["Arn"] as? String ?? ""
        roleArn = dict["RoleArn"] as? String
        input = dict["Input"] as? String
        inputPath = dict["InputPath"] as? String

        if let dlc = dict["DeadLetterConfig"] as? [String: Any] {
            deadLetterArn = dlc["Arn"] as? String
        } else {
            deadLetterArn = nil
        }
    }
}

struct PutEventsResultEntry: Hashable {
    let eventId: String?
    let errorCode: String?
    let errorMessage: String?

    init(from dict: [String: Any]) {
        eventId = dict["EventId"] as? String
        errorCode = dict["ErrorCode"] as? String
        errorMessage = dict["ErrorMessage"] as? String
    }
}

struct PutEventsResult {
    let failedEntryCount: Int
    let entries: [PutEventsResultEntry]

    init(from dict: [String: Any]) {
        failedEntryCount = dict["FailedEntryCount"] as? Int ?? 0
        if let entryDicts = dict["Entries"] as? [[String: Any]] {
            entries = entryDicts.map { PutEventsResultEntry(from: $0) }
        } else {
            entries = []
        }
    }
}
