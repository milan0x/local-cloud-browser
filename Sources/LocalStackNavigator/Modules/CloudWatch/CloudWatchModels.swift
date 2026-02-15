import Foundation
import SwiftUI

// MARK: - Tab & Enums

enum CloudWatchTab: String, CaseIterable {
    case metrics = "Metrics"
    case alarms = "Alarms"
}

enum CloudWatchTimeRange: String, CaseIterable {
    case oneHour = "1h"
    case threeHours = "3h"
    case twelveHours = "12h"
    case oneDay = "1d"
    case threeDays = "3d"
    case sevenDays = "7d"

    var seconds: Int {
        switch self {
        case .oneHour: 3600
        case .threeHours: 10800
        case .twelveHours: 43200
        case .oneDay: 86400
        case .threeDays: 259200
        case .sevenDays: 604800
        }
    }

    var displayLabel: String { rawValue }

    /// Suggested period (data resolution) in seconds for this time range.
    var suggestedPeriod: Int {
        switch self {
        case .oneHour: 60
        case .threeHours: 300
        case .twelveHours: 300
        case .oneDay: 300
        case .threeDays: 3600
        case .sevenDays: 3600
        }
    }
}

enum CloudWatchStatistic: String, CaseIterable {
    case average = "Average"
    case sum = "Sum"
    case minimum = "Minimum"
    case maximum = "Maximum"
    case sampleCount = "SampleCount"
}

enum CloudWatchAlarmState: String {
    case ok = "OK"
    case alarm = "ALARM"
    case insufficientData = "INSUFFICIENT_DATA"

    var displayName: String {
        switch self {
        case .ok: "OK"
        case .alarm: "ALARM"
        case .insufficientData: "INSUFFICIENT DATA"
        }
    }

    var color: Color {
        switch self {
        case .ok: .green
        case .alarm: .red
        case .insufficientData: .orange
        }
    }
}

enum CloudWatchComparisonOperator: String, CaseIterable {
    case greaterThanOrEqualToThreshold = "GreaterThanOrEqualToThreshold"
    case greaterThanThreshold = "GreaterThanThreshold"
    case lessThanThreshold = "LessThanThreshold"
    case lessThanOrEqualToThreshold = "LessThanOrEqualToThreshold"
    case lessThanLowerOrGreaterThanUpperThreshold = "LessThanLowerOrGreaterThanUpperThreshold"
    case greaterThanUpperThreshold = "GreaterThanUpperThreshold"

    var displayName: String {
        switch self {
        case .greaterThanOrEqualToThreshold: ">="
        case .greaterThanThreshold: ">"
        case .lessThanThreshold: "<"
        case .lessThanOrEqualToThreshold: "<="
        case .lessThanLowerOrGreaterThanUpperThreshold: "< lower or > upper"
        case .greaterThanUpperThreshold: "> upper"
        }
    }
}

// MARK: - Metric Unit

enum CloudWatchUnit: String, CaseIterable {
    case none = "None"
    case count = "Count"
    case seconds = "Seconds"
    case microseconds = "Microseconds"
    case milliseconds = "Milliseconds"
    case bytes = "Bytes"
    case kilobytes = "Kilobytes"
    case megabytes = "Megabytes"
    case gigabytes = "Gigabytes"
    case percent = "Percent"
    case countPerSecond = "Count/Second"
    case bytesPerSecond = "Bytes/Second"
}

// MARK: - Models

struct CloudWatchDimension: Hashable {
    let name: String
    let value: String

    init(name: String, value: String) {
        self.name = name
        self.value = value
    }

    init(from dict: [String: Any]) {
        name = dict["Name"] as? String ?? ""
        value = dict["Value"] as? String ?? ""
    }

    func toPayload() -> [String: String] {
        ["Name": name, "Value": value]
    }
}

struct CloudWatchMetric: Identifiable, Hashable {
    let namespace: String
    let metricName: String
    let dimensions: [CloudWatchDimension]

    var id: String { "\(namespace)/\(metricName)/\(dimensions.map { "\($0.name)=\($0.value)" }.joined(separator: ","))" }

    init(namespace: String, metricName: String, dimensions: [CloudWatchDimension] = []) {
        self.namespace = namespace
        self.metricName = metricName
        self.dimensions = dimensions
    }

    init(from dict: [String: Any]) {
        namespace = dict["Namespace"] as? String ?? ""
        metricName = dict["MetricName"] as? String ?? ""
        if let dims = dict["Dimensions"] as? [[String: Any]] {
            dimensions = dims.map { CloudWatchDimension(from: $0) }
        } else {
            dimensions = []
        }
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func listMetricsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws cloudwatch list-metrics \\",
            "  --namespace '\(Self.shellEscape(namespace))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listAllMetricsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws cloudwatch list-metrics \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}

struct CloudWatchDatapoint: Identifiable, Hashable {
    let timestamp: Date
    let average: Double?
    let sum: Double?
    let minimum: Double?
    let maximum: Double?
    let sampleCount: Double?
    let unit: String

    var id: Date { timestamp }

    func value(for statistic: CloudWatchStatistic) -> Double? {
        switch statistic {
        case .average: average
        case .sum: sum
        case .minimum: minimum
        case .maximum: maximum
        case .sampleCount: sampleCount
        }
    }

    init(from dict: [String: Any]) {
        if let ts = dict["Timestamp"] as? String {
            timestamp = ISO8601DateFormatter().date(from: ts) ?? Date()
        } else if let ts = dict["Timestamp"] as? Double {
            timestamp = Date(timeIntervalSince1970: ts)
        } else {
            timestamp = Date()
        }
        average = dict["Average"] as? Double
        sum = dict["Sum"] as? Double
        minimum = dict["Minimum"] as? Double
        maximum = dict["Maximum"] as? Double
        sampleCount = dict["SampleCount"] as? Double
        unit = dict["Unit"] as? String ?? "None"
    }
}

struct CloudWatchAlarm: Identifiable, Hashable {
    let alarmName: String
    let alarmArn: String
    let stateValue: String
    let stateReason: String
    let namespace: String
    let metricName: String
    let statistic: String
    let period: Int
    let evaluationPeriods: Int
    let comparisonOperator: String
    let threshold: Double
    let dimensions: [CloudWatchDimension]
    let alarmActions: [String]
    let updatedTimestamp: Date?

    var id: String { alarmName }

    var alarmState: CloudWatchAlarmState {
        CloudWatchAlarmState(rawValue: stateValue) ?? .insufficientData
    }

    var thresholdDescription: String {
        let op = CloudWatchComparisonOperator(rawValue: comparisonOperator)?.displayName ?? comparisonOperator
        let thresholdStr = threshold.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", threshold)
            : String(format: "%.2f", threshold)
        return "\(statistic) of \(metricName) \(op) \(thresholdStr) for \(evaluationPeriods) period(s)"
    }

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeAlarmCLI(endpointUrl: String, region: String) -> String {
        [
            "aws cloudwatch describe-alarms \\",
            "  --alarm-names '\(Self.shellEscape(alarmName))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listAlarmsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws cloudwatch describe-alarms \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        alarmName = dict["AlarmName"] as? String ?? ""
        alarmArn = dict["AlarmArn"] as? String ?? ""
        stateValue = dict["StateValue"] as? String ?? "INSUFFICIENT_DATA"
        stateReason = dict["StateReason"] as? String ?? ""
        namespace = dict["Namespace"] as? String ?? ""
        metricName = dict["MetricName"] as? String ?? ""
        statistic = dict["Statistic"] as? String ?? "Average"
        period = dict["Period"] as? Int ?? 300
        evaluationPeriods = dict["EvaluationPeriods"] as? Int ?? 1
        comparisonOperator = dict["ComparisonOperator"] as? String ?? ""
        threshold = dict["Threshold"] as? Double ?? 0
        alarmActions = dict["AlarmActions"] as? [String] ?? []
        if let dims = dict["Dimensions"] as? [[String: Any]] {
            dimensions = dims.map { CloudWatchDimension(from: $0) }
        } else {
            dimensions = []
        }
        if let ts = dict["StateUpdatedTimestamp"] as? String {
            updatedTimestamp = ISO8601DateFormatter().date(from: ts)
        } else if let ts = dict["StateUpdatedTimestamp"] as? Double {
            updatedTimestamp = Date(timeIntervalSince1970: ts)
        } else {
            updatedTimestamp = nil
        }
    }
}
