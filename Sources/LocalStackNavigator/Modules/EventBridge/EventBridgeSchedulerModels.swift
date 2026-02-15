import Foundation

enum EventBridgeTab: String, CaseIterable {
    case events = "Events"
    case schedules = "Schedules"
}

// MARK: - Schedule Groups

struct SchedulerScheduleGroup: Identifiable, Hashable {
    let name: String
    let arn: String?
    let state: String?
    let creationDate: Date?
    let lastModificationDate: Date?

    var id: String { name }

    var isDefault: Bool { name == "default" }

    init(from dict: [String: Any]) {
        name = dict["Name"] as? String ?? ""
        arn = dict["Arn"] as? String
        state = dict["State"] as? String

        if let ts = dict["CreationDate"] as? Double {
            creationDate = Date(timeIntervalSince1970: ts)
        } else if let str = dict["CreationDate"] as? String {
            creationDate = ISO8601DateFormatter().date(from: str)
        } else {
            creationDate = nil
        }

        if let ts = dict["LastModificationDate"] as? Double {
            lastModificationDate = Date(timeIntervalSince1970: ts)
        } else if let str = dict["LastModificationDate"] as? String {
            lastModificationDate = ISO8601DateFormatter().date(from: str)
        } else {
            lastModificationDate = nil
        }
    }
}

// MARK: - Schedules

struct SchedulerSchedule: Identifiable, Hashable {
    let name: String
    let arn: String?
    let groupName: String?
    let scheduleExpression: String?
    let scheduleExpressionTimezone: String?
    let state: String
    let description: String?
    let targetArn: String?
    let targetRoleArn: String?
    let targetInput: String?
    let flexibleTimeWindowMode: String?
    let flexibleTimeWindowMaximumWindowInMinutes: Int?
    let creationDate: Date?
    let lastModificationDate: Date?

    var id: String { name }

    var isEnabled: Bool { state == "ENABLED" }

    var targetServiceType: SchedulerTargetServiceType {
        guard let arn = targetArn else { return .other("Unknown") }
        return SchedulerTargetServiceType.from(arn: arn)
    }

    var prettyTargetInput: String? {
        guard let input = targetInput,
              let data = input.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return targetInput
        }
        return result
    }

    init(from dict: [String: Any]) {
        name = dict["Name"] as? String ?? ""
        arn = dict["Arn"] as? String
        groupName = dict["GroupName"] as? String
        scheduleExpression = dict["ScheduleExpression"] as? String
        scheduleExpressionTimezone = dict["ScheduleExpressionTimezone"] as? String
        state = dict["State"] as? String ?? "ENABLED"
        description = dict["Description"] as? String

        // Target is nested
        if let target = dict["Target"] as? [String: Any] {
            targetArn = target["Arn"] as? String
            targetRoleArn = target["RoleArn"] as? String
            targetInput = target["Input"] as? String
        } else {
            targetArn = nil
            targetRoleArn = nil
            targetInput = nil
        }

        // Flexible time window
        if let ftw = dict["FlexibleTimeWindow"] as? [String: Any] {
            flexibleTimeWindowMode = ftw["Mode"] as? String
            flexibleTimeWindowMaximumWindowInMinutes = ftw["MaximumWindowInMinutes"] as? Int
        } else {
            flexibleTimeWindowMode = nil
            flexibleTimeWindowMaximumWindowInMinutes = nil
        }

        if let ts = dict["CreationDate"] as? Double {
            creationDate = Date(timeIntervalSince1970: ts)
        } else if let str = dict["CreationDate"] as? String {
            creationDate = ISO8601DateFormatter().date(from: str)
        } else {
            creationDate = nil
        }

        if let ts = dict["LastModificationDate"] as? Double {
            lastModificationDate = Date(timeIntervalSince1970: ts)
        } else if let str = dict["LastModificationDate"] as? String {
            lastModificationDate = ISO8601DateFormatter().date(from: str)
        } else {
            lastModificationDate = nil
        }
    }
}

// MARK: - Target Service Type

enum SchedulerTargetServiceType: Hashable {
    case lambda
    case stepFunctions
    case sqs
    case sns
    case other(String)

    var displayName: String {
        switch self {
        case .lambda: "Lambda"
        case .stepFunctions: "Step Functions"
        case .sqs: "SQS"
        case .sns: "SNS"
        case .other(let service): service
        }
    }

    var systemImage: String {
        switch self {
        case .lambda: "function"
        case .stepFunctions: "arrow.triangle.branch"
        case .sqs: "tray.2"
        case .sns: "bell"
        case .other: "questionmark.circle"
        }
    }

    static func from(arn: String) -> SchedulerTargetServiceType {
        // ARN format: arn:aws:<service>:<region>:<account>:...
        let components = arn.split(separator: ":")
        guard components.count >= 3 else { return .other("Unknown") }
        let service = String(components[2])
        switch service {
        case "lambda": return .lambda
        case "states": return .stepFunctions
        case "sqs": return .sqs
        case "sns": return .sns
        default: return .other(service)
        }
    }
}
