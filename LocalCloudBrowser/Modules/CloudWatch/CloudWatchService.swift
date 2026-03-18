import Foundation

final class CloudWatchService: BaseService {
    // MARK: - Metrics

    func listMetricsPage(namespace: String? = nil, region: String? = nil, token: String? = nil) async throws -> ([CloudWatchMetric], String?) {
        var payload: [String: Any] = [:]
        if let namespace {
            payload["Namespace"] = namespace
        }
        if let token {
            payload["NextToken"] = token
        }

        let data = try await client.cloudWatchRequest(action: "ListMetrics", payload: payload, region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }

        let metrics = (json["Metrics"] as? [[String: Any]] ?? []).map { CloudWatchMetric(from: $0) }
        return (metrics, json["NextToken"] as? String)
    }

    func listMetrics(namespace: String? = nil, region: String? = nil) async throws -> [CloudWatchMetric] {
        var allMetrics: [CloudWatchMetric] = []
        var nextToken: String? = nil

        repeat {
            let (metrics, token) = try await listMetricsPage(namespace: namespace, region: region, token: nextToken)
            allMetrics.append(contentsOf: metrics)
            nextToken = token
            if allMetrics.count >= 10_000 { break }
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
            "StartTime": DateFormatters.iso8601.string(from: startTime),
            "EndTime": DateFormatters.iso8601.string(from: endTime),
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

    func describeAlarmsPage(region: String? = nil, token: String? = nil) async throws -> ([CloudWatchAlarm], String?) {
        var payload: [String: Any] = [:]
        if let token {
            payload["NextToken"] = token
        }

        let data = try await client.cloudWatchRequest(action: "DescribeAlarms", payload: payload, region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }

        let alarms = (json["MetricAlarms"] as? [[String: Any]] ?? []).map { CloudWatchAlarm(from: $0) }
        return (alarms, json["NextToken"] as? String)
    }

    func describeAlarms(region: String? = nil) async throws -> [CloudWatchAlarm] {
        var allAlarms: [CloudWatchAlarm] = []
        var nextToken: String? = nil

        repeat {
            let (alarms, token) = try await describeAlarmsPage(region: region, token: nextToken)
            allAlarms.append(contentsOf: alarms)
            nextToken = token
            if allAlarms.count >= 10_000 { break }
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
