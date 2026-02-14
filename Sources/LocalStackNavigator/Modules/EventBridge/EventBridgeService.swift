import Foundation

@MainActor
final class EventBridgeService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Event Buses

    func listEventBuses() async throws -> [EventBridgeBus] {
        var allBuses: [EventBridgeBus] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.eventBridgeRequest(action: "ListEventBuses", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let buses = json["EventBuses"] as? [[String: Any]] {
                allBuses.append(contentsOf: buses.map { EventBridgeBus(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allBuses
    }

    func createEventBus(name: String) async throws {
        _ = try await client.eventBridgeRequest(
            action: "CreateEventBus",
            payload: ["Name": name]
        )
    }

    func deleteEventBus(name: String) async throws {
        _ = try await client.eventBridgeRequest(
            action: "DeleteEventBus",
            payload: ["Name": name]
        )
    }

    // MARK: - Rules

    func listRules(eventBusName: String) async throws -> [EventBridgeRule] {
        var allRules: [EventBridgeRule] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = ["EventBusName": eventBusName]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.eventBridgeRequest(action: "ListRules", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let rules = json["Rules"] as? [[String: Any]] {
                allRules.append(contentsOf: rules.map { EventBridgeRule(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allRules
    }

    func describeRule(name: String, eventBusName: String) async throws -> EventBridgeRule {
        let data = try await client.eventBridgeRequest(
            action: "DescribeRule",
            payload: ["Name": name, "EventBusName": eventBusName]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return EventBridgeRule(from: json)
    }

    func putRule(
        name: String,
        description: String?,
        eventBusName: String,
        eventPattern: String?,
        scheduleExpression: String?,
        state: String
    ) async throws {
        var payload: [String: Any] = [
            "Name": name,
            "EventBusName": eventBusName,
            "State": state,
        ]
        if let desc = description, !desc.isEmpty {
            payload["Description"] = desc
        }
        if let pattern = eventPattern, !pattern.isEmpty {
            payload["EventPattern"] = pattern
        }
        if let schedule = scheduleExpression, !schedule.isEmpty {
            payload["ScheduleExpression"] = schedule
        }
        _ = try await client.eventBridgeRequest(action: "PutRule", payload: payload)
    }

    func deleteRule(name: String, eventBusName: String) async throws {
        _ = try await client.eventBridgeRequest(
            action: "DeleteRule",
            payload: ["Name": name, "EventBusName": eventBusName]
        )
    }

    func enableRule(name: String, eventBusName: String) async throws {
        _ = try await client.eventBridgeRequest(
            action: "EnableRule",
            payload: ["Name": name, "EventBusName": eventBusName]
        )
    }

    func disableRule(name: String, eventBusName: String) async throws {
        _ = try await client.eventBridgeRequest(
            action: "DisableRule",
            payload: ["Name": name, "EventBusName": eventBusName]
        )
    }

    // MARK: - Targets

    func listTargetsByRule(ruleName: String, eventBusName: String) async throws -> [EventBridgeTarget] {
        var allTargets: [EventBridgeTarget] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = [
                "Rule": ruleName,
                "EventBusName": eventBusName,
            ]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.eventBridgeRequest(action: "ListTargetsByRule", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let targets = json["Targets"] as? [[String: Any]] {
                allTargets.append(contentsOf: targets.map { EventBridgeTarget(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allTargets
    }

    func putTargets(ruleName: String, eventBusName: String, targets: [[String: Any]]) async throws {
        _ = try await client.eventBridgeRequest(
            action: "PutTargets",
            payload: [
                "Rule": ruleName,
                "EventBusName": eventBusName,
                "Targets": targets,
            ]
        )
    }

    func removeTargets(ruleName: String, eventBusName: String, ids: [String]) async throws {
        _ = try await client.eventBridgeRequest(
            action: "RemoveTargets",
            payload: [
                "Rule": ruleName,
                "EventBusName": eventBusName,
                "Ids": ids,
            ]
        )
    }

    // MARK: - Put Events

    func putEvents(entries: [[String: Any]]) async throws -> PutEventsResult {
        let data = try await client.eventBridgeRequest(
            action: "PutEvents",
            payload: ["Entries": entries]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return PutEventsResult(from: [:])
        }
        return PutEventsResult(from: json)
    }
}
