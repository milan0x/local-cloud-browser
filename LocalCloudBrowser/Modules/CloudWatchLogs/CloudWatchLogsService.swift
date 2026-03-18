import Foundation

struct LogEventsResult {
    let events: [CloudWatchLogEvent]
    let nextForwardToken: String?
    let nextBackwardToken: String?
}

struct FilteredLogEventsResult {
    let events: [CloudWatchFilteredLogEvent]
    let nextToken: String?
}

final class CloudWatchLogsService: BaseService {
    // MARK: - Log Groups

    func describeLogGroupsPage(token: String? = nil, region: String? = nil) async throws -> ([CloudWatchLogGroup], String?) {
        var payload: [String: Any] = [:]
        if let token {
            payload["nextToken"] = token
        }
        let data = try await client.cloudWatchLogsRequest(action: "DescribeLogGroups", payload: payload, region: region)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        let groups = (json["logGroups"] as? [[String: Any]] ?? []).map { CloudWatchLogGroup(from: $0) }
        return (groups, json["nextToken"] as? String)
    }

    func describeLogGroups(region: String? = nil) async throws -> [CloudWatchLogGroup] {
        var allGroups: [CloudWatchLogGroup] = []
        var nextToken: String? = nil
        repeat {
            let (groups, token) = try await describeLogGroupsPage(token: nextToken, region: region)
            allGroups.append(contentsOf: groups)
            nextToken = token
            if allGroups.count >= 10_000 { break }
        } while nextToken != nil
        return allGroups
    }

    // MARK: - Log Streams

    func describeLogStreamsPage(logGroupName: String, token: String? = nil) async throws -> ([CloudWatchLogStream], String?) {
        var payload: [String: Any] = [
            "logGroupName": logGroupName,
            "orderBy": "LastEventTime",
            "descending": true,
        ]
        if let token {
            payload["nextToken"] = token
        }
        let data = try await client.cloudWatchLogsRequest(action: "DescribeLogStreams", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        let streams = (json["logStreams"] as? [[String: Any]] ?? []).map { CloudWatchLogStream(from: $0) }
        return (streams, json["nextToken"] as? String)
    }

    func describeLogStreams(logGroupName: String) async throws -> [CloudWatchLogStream] {
        var allStreams: [CloudWatchLogStream] = []
        var nextToken: String? = nil
        repeat {
            let (streams, token) = try await describeLogStreamsPage(logGroupName: logGroupName, token: nextToken)
            allStreams.append(contentsOf: streams)
            nextToken = token
            if allStreams.count >= 10_000 { break }
        } while nextToken != nil
        return allStreams
    }

    // MARK: - Log Events

    func getLogEvents(
        logGroupName: String,
        logStreamName: String,
        startFromHead: Bool = true,
        nextToken: String? = nil,
        limit: Int = 100
    ) async throws -> LogEventsResult {
        var payload: [String: Any] = [
            "logGroupName": logGroupName,
            "logStreamName": logStreamName,
            "startFromHead": startFromHead,
            "limit": limit,
        ]
        if let token = nextToken {
            payload["nextToken"] = token
        }
        let data = try await client.cloudWatchLogsRequest(action: "GetLogEvents", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LogEventsResult(events: [], nextForwardToken: nil, nextBackwardToken: nil)
        }
        let events = (json["events"] as? [[String: Any]] ?? []).map { CloudWatchLogEvent(from: $0) }
        return LogEventsResult(
            events: events,
            nextForwardToken: json["nextForwardToken"] as? String,
            nextBackwardToken: json["nextBackwardToken"] as? String
        )
    }

    // MARK: - Filter Log Events

    func filterLogEvents(
        logGroupName: String,
        filterPattern: String? = nil,
        startTime: Date? = nil,
        endTime: Date? = nil,
        nextToken: String? = nil,
        limit: Int = 100
    ) async throws -> FilteredLogEventsResult {
        var payload: [String: Any] = [
            "logGroupName": logGroupName,
            "limit": limit,
        ]
        if let pattern = filterPattern, !pattern.isEmpty {
            payload["filterPattern"] = pattern
        }
        if let start = startTime {
            payload["startTime"] = Int64(start.timeIntervalSince1970 * 1000)
        }
        if let end = endTime {
            payload["endTime"] = Int64(end.timeIntervalSince1970 * 1000)
        }
        if let token = nextToken {
            payload["nextToken"] = token
        }
        let data = try await client.cloudWatchLogsRequest(action: "FilterLogEvents", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return FilteredLogEventsResult(events: [], nextToken: nil)
        }
        let events = (json["events"] as? [[String: Any]] ?? []).map { CloudWatchFilteredLogEvent(from: $0) }
        return FilteredLogEventsResult(
            events: events,
            nextToken: json["nextToken"] as? String
        )
    }

    // MARK: - Create / Delete

    func createLogGroup(name: String) async throws {
        _ = try await client.cloudWatchLogsRequest(
            action: "CreateLogGroup",
            payload: ["logGroupName": name]
        )
    }

    func createLogStream(logGroupName: String, logStreamName: String) async throws {
        _ = try await client.cloudWatchLogsRequest(
            action: "CreateLogStream",
            payload: [
                "logGroupName": logGroupName,
                "logStreamName": logStreamName,
            ]
        )
    }

    func putLogEvents(logGroupName: String, logStreamName: String, message: String) async throws {
        let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
        let logEvent: [String: Any] = [
            "timestamp": timestamp,
            "message": message,
        ]
        _ = try await client.cloudWatchLogsRequest(
            action: "PutLogEvents",
            payload: [
                "logGroupName": logGroupName,
                "logStreamName": logStreamName,
                "logEvents": [logEvent],
            ]
        )
    }

    func deleteLogGroup(name: String) async throws {
        _ = try await client.cloudWatchLogsRequest(
            action: "DeleteLogGroup",
            payload: ["logGroupName": name]
        )
    }

    func deleteLogStream(logGroupName: String, logStreamName: String) async throws {
        _ = try await client.cloudWatchLogsRequest(
            action: "DeleteLogStream",
            payload: [
                "logGroupName": logGroupName,
                "logStreamName": logStreamName,
            ]
        )
    }
}
