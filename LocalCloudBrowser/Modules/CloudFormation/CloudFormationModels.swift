import Foundation

struct CloudFormationStack: Identifiable, Hashable {
    let stackName: String
    let stackId: String
    let stackStatus: String
    let creationTime: Date?
    let templateDescription: String?

    var id: String { stackId }

    var statusColor: StatusColor {
        let upper = stackStatus.uppercased()
        if upper.contains("COMPLETE") && !upper.contains("ROLLBACK") && !upper.contains("FAILED") {
            return .green
        } else if upper.contains("IN_PROGRESS") {
            return .blue
        } else if upper.contains("FAILED") {
            return .red
        } else if upper.contains("ROLLBACK") {
            return .orange
        }
        return .gray
    }

    enum StatusColor {
        case green, blue, red, orange, gray

        var swiftUIColor: SwiftUI.Color {
            switch self {
            case .green: .green
            case .blue: .blue
            case .red: .red
            case .orange: .orange
            case .gray: .gray
            }
        }
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeStackCLI(endpointUrl: String, region: String) -> String {
        [
            "aws cloudformation describe-stacks \\",
            "  --stack-name '\(Self.shellEscape(stackName))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    func listResourcesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws cloudformation list-stack-resources \\",
            "  --stack-name '\(Self.shellEscape(stackName))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    private nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private nonisolated(unsafe) static let iso8601NoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return iso8601.date(from: string) ?? iso8601NoFraction.date(from: string)
    }

    init(from dict: [String: String]) {
        stackName = dict["StackName"] ?? ""
        stackId = dict["StackId"] ?? ""
        stackStatus = dict["StackStatus"] ?? ""
        creationTime = Self.parseDate(dict["CreationTime"])
        templateDescription = dict["TemplateDescription"]
    }
}

import SwiftUI

struct CloudFormationStackDetail: Identifiable, Hashable {
    let stackName: String
    let stackId: String
    let stackStatus: String
    let creationTime: Date?
    let lastUpdatedTime: Date?
    let templateDescription: String?
    let capabilities: [String]
    let roleARN: String?
    let parameters: [CFParameter]
    let outputs: [CFOutput]

    var id: String { stackId }

    var statusColor: CloudFormationStack.StatusColor {
        let upper = stackStatus.uppercased()
        if upper.contains("COMPLETE") && !upper.contains("ROLLBACK") && !upper.contains("FAILED") {
            return .green
        } else if upper.contains("IN_PROGRESS") {
            return .blue
        } else if upper.contains("FAILED") {
            return .red
        } else if upper.contains("ROLLBACK") {
            return .orange
        }
        return .gray
    }
}

struct CFParameter: Identifiable, Hashable {
    let parameterKey: String
    let parameterValue: String

    var id: String { parameterKey }

    init(parameterKey: String, parameterValue: String) {
        self.parameterKey = parameterKey
        self.parameterValue = parameterValue
    }

    init(from dict: [String: String]) {
        parameterKey = dict["ParameterKey"] ?? ""
        parameterValue = dict["ParameterValue"] ?? ""
    }
}

struct CFOutput: Identifiable, Hashable {
    let outputKey: String
    let outputValue: String
    let description: String?
    let exportName: String?

    var id: String { outputKey }

    init(from dict: [String: String]) {
        outputKey = dict["OutputKey"] ?? ""
        outputValue = dict["OutputValue"] ?? ""
        description = dict["Description"]
        exportName = dict["ExportName"]
    }
}

struct CloudFormationResource: Identifiable, Hashable {
    let logicalResourceId: String
    let physicalResourceId: String?
    let resourceType: String
    let resourceStatus: String
    let lastUpdatedTimestamp: Date?

    var id: String { logicalResourceId }

    var statusColor: CloudFormationStack.StatusColor {
        let upper = resourceStatus.uppercased()
        if upper.contains("COMPLETE") && !upper.contains("ROLLBACK") && !upper.contains("FAILED") {
            return .green
        } else if upper.contains("IN_PROGRESS") {
            return .blue
        } else if upper.contains("FAILED") {
            return .red
        } else if upper.contains("ROLLBACK") {
            return .orange
        }
        return .gray
    }

    /// Strip `AWS::` prefix from resource type for compact display.
    var shortType: String {
        if resourceType.hasPrefix("AWS::") {
            return String(resourceType.dropFirst(5))
        }
        return resourceType
    }

    init(from dict: [String: String]) {
        logicalResourceId = dict["LogicalResourceId"] ?? ""
        physicalResourceId = dict["PhysicalResourceId"]
        resourceType = dict["ResourceType"] ?? ""
        resourceStatus = dict["ResourceStatus"] ?? ""
        lastUpdatedTimestamp = CloudFormationStack.parseDate(dict["LastUpdatedTimestamp"] ?? dict["Timestamp"])
    }
}

struct CloudFormationEvent: Identifiable, Hashable {
    let eventId: String
    let logicalResourceId: String?
    let physicalResourceId: String?
    let resourceType: String?
    let resourceStatus: String?
    let resourceStatusReason: String?
    let timestamp: Date?

    var id: String { eventId }

    var statusColor: CloudFormationStack.StatusColor {
        guard let status = resourceStatus?.uppercased() else { return .gray }
        if status.contains("COMPLETE") && !status.contains("ROLLBACK") && !status.contains("FAILED") {
            return .green
        } else if status.contains("IN_PROGRESS") {
            return .blue
        } else if status.contains("FAILED") {
            return .red
        } else if status.contains("ROLLBACK") {
            return .orange
        }
        return .gray
    }

    init(from dict: [String: String]) {
        eventId = dict["EventId"] ?? UUID().uuidString
        logicalResourceId = dict["LogicalResourceId"]
        physicalResourceId = dict["PhysicalResourceId"]
        resourceType = dict["ResourceType"]
        resourceStatus = dict["ResourceStatus"]
        resourceStatusReason = dict["ResourceStatusReason"]
        timestamp = CloudFormationStack.parseDate(dict["Timestamp"])
    }
}
