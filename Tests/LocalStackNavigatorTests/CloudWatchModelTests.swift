import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("CloudWatch Models")
struct CloudWatchModelTests {

    // MARK: - CloudWatchTimeRange

    @Test("seconds returns correct values")
    func timeRangeSeconds() {
        #expect(CloudWatchTimeRange.oneHour.seconds == 3600)
        #expect(CloudWatchTimeRange.threeHours.seconds == 10800)
        #expect(CloudWatchTimeRange.twelveHours.seconds == 43200)
        #expect(CloudWatchTimeRange.oneDay.seconds == 86400)
        #expect(CloudWatchTimeRange.threeDays.seconds == 259200)
        #expect(CloudWatchTimeRange.sevenDays.seconds == 604800)
    }

    @Test("suggestedPeriod returns appropriate values")
    func timeRangeSuggestedPeriod() {
        #expect(CloudWatchTimeRange.oneHour.suggestedPeriod == 60)
        #expect(CloudWatchTimeRange.threeHours.suggestedPeriod == 300)
        #expect(CloudWatchTimeRange.sevenDays.suggestedPeriod == 3600)
    }

    // MARK: - CloudWatchAlarmState

    @Test("displayName maps states correctly")
    func alarmStateDisplayName() {
        #expect(CloudWatchAlarmState.ok.displayName == "OK")
        #expect(CloudWatchAlarmState.alarm.displayName == "ALARM")
        #expect(CloudWatchAlarmState.insufficientData.displayName == "INSUFFICIENT DATA")
    }

    // MARK: - CloudWatchComparisonOperator

    @Test("displayName maps operators to symbols")
    func comparisonOperatorDisplayName() {
        #expect(CloudWatchComparisonOperator.greaterThanOrEqualToThreshold.displayName == ">=")
        #expect(CloudWatchComparisonOperator.greaterThanThreshold.displayName == ">")
        #expect(CloudWatchComparisonOperator.lessThanThreshold.displayName == "<")
        #expect(CloudWatchComparisonOperator.lessThanOrEqualToThreshold.displayName == "<=")
    }

    // MARK: - CloudWatchAlarm

    @Test("alarmState parses state value")
    func alarmState() {
        let alarm = CloudWatchAlarm(from: ["AlarmName": "test", "StateValue": "OK"])
        #expect(alarm.alarmState == .ok)

        let alarm2 = CloudWatchAlarm(from: ["AlarmName": "test", "StateValue": "ALARM"])
        #expect(alarm2.alarmState == .alarm)
    }

    @Test("alarmState defaults to insufficientData for unknown")
    func alarmStateDefault() {
        let alarm = CloudWatchAlarm(from: ["AlarmName": "test", "StateValue": "UNKNOWN"])
        #expect(alarm.alarmState == .insufficientData)
    }

    @Test("thresholdDescription formats correctly")
    func thresholdDescription() {
        let alarm = CloudWatchAlarm(from: [
            "AlarmName": "test",
            "Statistic": "Average",
            "MetricName": "CPUUtilization",
            "ComparisonOperator": "GreaterThanThreshold",
            "Threshold": 80.0,
            "EvaluationPeriods": 3,
        ])
        #expect(alarm.thresholdDescription.contains("Average"))
        #expect(alarm.thresholdDescription.contains("CPUUtilization"))
        #expect(alarm.thresholdDescription.contains(">"))
        #expect(alarm.thresholdDescription.contains("80"))
        #expect(alarm.thresholdDescription.contains("3 period(s)"))
    }

    // MARK: - CloudWatchDatapoint

    @Test("value(for:) returns correct statistic")
    func datapointValueFor() {
        let dp = CloudWatchDatapoint(from: [
            "Timestamp": "2024-01-15T00:00:00Z",
            "Average": 42.5,
            "Sum": 100.0,
            "Minimum": 10.0,
            "Maximum": 90.0,
            "SampleCount": 5.0,
        ])
        #expect(dp.value(for: .average) == 42.5)
        #expect(dp.value(for: .sum) == 100.0)
        #expect(dp.value(for: .minimum) == 10.0)
        #expect(dp.value(for: .maximum) == 90.0)
        #expect(dp.value(for: .sampleCount) == 5.0)
    }

    // MARK: - CloudWatchMetric

    @Test("metric id includes namespace and dimensions")
    func metricId() {
        let metric = CloudWatchMetric(
            namespace: "AWS/EC2",
            metricName: "CPUUtilization",
            dimensions: [CloudWatchDimension(name: "InstanceId", value: "i-123")]
        )
        #expect(metric.id.contains("AWS/EC2"))
        #expect(metric.id.contains("CPUUtilization"))
        #expect(metric.id.contains("InstanceId=i-123"))
    }

    // MARK: - CLI

    @Test("listMetricsCLI generates valid command")
    func listMetricsCLI() {
        let metric = CloudWatchMetric(namespace: "AWS/EC2", metricName: "CPU")
        let cli = metric.listMetricsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws cloudwatch list-metrics"))
        #expect(cli.contains("AWS/EC2"))
    }

    @Test("describeAlarmCLI generates valid command")
    func describeAlarmCLI() {
        let alarm = CloudWatchAlarm(from: ["AlarmName": "my-alarm"])
        let cli = alarm.describeAlarmCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws cloudwatch describe-alarms"))
        #expect(cli.contains("my-alarm"))
    }
}
