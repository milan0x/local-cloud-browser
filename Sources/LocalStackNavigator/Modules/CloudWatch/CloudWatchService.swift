import Foundation

@MainActor
final class CloudWatchService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Metrics

    func listMetrics(namespace: String? = nil) async throws -> [CloudWatchMetric] {
        var allMetrics: [CloudWatchMetric] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = [:]
            if let namespace {
                payload["Namespace"] = namespace
            }
            if let nextToken {
                payload["NextToken"] = nextToken
            }

            let data = try await client.cloudWatchRequest(action: "ListMetrics", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }

            if let metrics = json["Metrics"] as? [[String: Any]] {
                allMetrics.append(contentsOf: metrics.map { CloudWatchMetric(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allMetrics
    }

    func getMetricStatistics(
        metric: CloudWatchMetric,
        startTime: Date,
        endTime: Date,
        period: Int,
        statistics: [CloudWatchStatistic]
    ) async throws -> [CloudWatchDatapoint] {
        var payload: [String: Any] = [
            "Namespace": metric.namespace,
            "MetricName": metric.metricName,
            "StartTime": ISO8601DateFormatter().string(from: startTime),
            "EndTime": ISO8601DateFormatter().string(from: endTime),
            "Period": period,
            "Statistics": statistics.map(\.rawValue),
        ]
        if !metric.dimensions.isEmpty {
            payload["Dimensions"] = metric.dimensions.map { $0.toPayload() }
        }

        let data = try await client.cloudWatchRequest(action: "GetMetricStatistics", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let datapoints = json["Datapoints"] as? [[String: Any]] else {
            return []
        }
        return datapoints
            .map { CloudWatchDatapoint(from: $0) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func putMetricData(
        namespace: String,
        metricName: String,
        value: Double,
        unit: String,
        dimensions: [CloudWatchDimension]
    ) async throws {
        var metricDatum: [String: Any] = [
            "MetricName": metricName,
            "Value": value,
            "Unit": unit,
        ]
        if !dimensions.isEmpty {
            metricDatum["Dimensions"] = dimensions.map { $0.toPayload() }
        }
        let payload: [String: Any] = [
            "Namespace": namespace,
            "MetricData": [metricDatum],
        ]
        _ = try await client.cloudWatchRequest(action: "PutMetricData", payload: payload)
    }

    // MARK: - Alarms

    func describeAlarms() async throws -> [CloudWatchAlarm] {
        var allAlarms: [CloudWatchAlarm] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = [:]
            if let nextToken {
                payload["NextToken"] = nextToken
            }

            let data = try await client.cloudWatchRequest(action: "DescribeAlarms", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }

            if let alarms = json["MetricAlarms"] as? [[String: Any]] {
                allAlarms.append(contentsOf: alarms.map { CloudWatchAlarm(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allAlarms
    }

    func putMetricAlarm(
        name: String,
        namespace: String,
        metricName: String,
        statistic: String,
        period: Int,
        evaluationPeriods: Int,
        comparisonOperator: String,
        threshold: Double
    ) async throws {
        let payload: [String: Any] = [
            "AlarmName": name,
            "Namespace": namespace,
            "MetricName": metricName,
            "Statistic": statistic,
            "Period": period,
            "EvaluationPeriods": evaluationPeriods,
            "ComparisonOperator": comparisonOperator,
            "Threshold": threshold,
        ]
        _ = try await client.cloudWatchRequest(action: "PutMetricAlarm", payload: payload)
    }

    func deleteAlarms(names: [String]) async throws {
        let payload: [String: Any] = [
            "AlarmNames": names,
        ]
        _ = try await client.cloudWatchRequest(action: "DeleteAlarms", payload: payload)
    }

    func setAlarmState(name: String, state: CloudWatchAlarmState, reason: String) async throws {
        let payload: [String: Any] = [
            "AlarmName": name,
            "StateValue": state.rawValue,
            "StateReason": reason,
        ]
        _ = try await client.cloudWatchRequest(action: "SetAlarmState", payload: payload)
    }
}
