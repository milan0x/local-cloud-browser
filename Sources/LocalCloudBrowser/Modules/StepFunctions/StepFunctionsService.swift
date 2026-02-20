import Foundation

final class StepFunctionsService: BaseService {
    // MARK: - State Machine Operations

    func listStateMachines(region: String? = nil) async throws -> [StateMachineSummary] {
        var allMachines: [StateMachineSummary] = []
        var nextToken: String?
        repeat {
            var payload: [String: Any] = ["maxResults": 100]
            if let token = nextToken {
                payload["nextToken"] = token
            }
            let data = try await client.stepFunctionsRequest(action: "ListStateMachines", payload: payload, region: region)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let machines = json["stateMachines"] as? [[String: Any]] else {
                break
            }
            allMachines.append(contentsOf: machines.map { StateMachineSummary(from: $0) })
            nextToken = json["nextToken"] as? String
        } while nextToken != nil
        return allMachines
    }

    func describeStateMachine(arn: String) async throws -> StateMachineDetail {
        let data = try await client.stepFunctionsRequest(
            action: "DescribeStateMachine",
            payload: ["stateMachineArn": arn]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return StateMachineDetail(from: json)
    }

    func createStateMachine(name: String, definition: String, roleArn: String, type: String) async throws {
        let payload: [String: Any] = [
            "name": name,
            "definition": definition,
            "roleArn": roleArn,
            "type": type,
        ]
        _ = try await client.stepFunctionsRequest(action: "CreateStateMachine", payload: payload)
    }

    func deleteStateMachine(arn: String) async throws {
        _ = try await client.stepFunctionsRequest(
            action: "DeleteStateMachine",
            payload: ["stateMachineArn": arn]
        )
    }

    // MARK: - Execution Operations

    func listExecutions(stateMachineArn: String) async throws -> [StepFunctionsExecution] {
        var allExecutions: [StepFunctionsExecution] = []
        var nextToken: String?
        repeat {
            var payload: [String: Any] = [
                "stateMachineArn": stateMachineArn,
                "maxResults": 100,
            ]
            if let token = nextToken {
                payload["nextToken"] = token
            }
            let data = try await client.stepFunctionsRequest(action: "ListExecutions", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let executions = json["executions"] as? [[String: Any]] else {
                break
            }
            allExecutions.append(contentsOf: executions.map { StepFunctionsExecution(from: $0) })
            nextToken = json["nextToken"] as? String
        } while nextToken != nil
        return allExecutions
    }

    func describeExecution(arn: String) async throws -> StepFunctionsExecutionDetail {
        let data = try await client.stepFunctionsRequest(
            action: "DescribeExecution",
            payload: ["executionArn": arn]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return StepFunctionsExecutionDetail(from: json)
    }

    func startExecution(stateMachineArn: String, name: String?, input: String?) async throws {
        var payload: [String: Any] = ["stateMachineArn": stateMachineArn]
        if let name, !name.isEmpty {
            payload["name"] = name
        }
        if let input, !input.isEmpty {
            payload["input"] = input
        }
        _ = try await client.stepFunctionsRequest(action: "StartExecution", payload: payload)
    }

    func stopExecution(arn: String, cause: String?, error: String?) async throws {
        var payload: [String: Any] = ["executionArn": arn]
        if let cause, !cause.isEmpty {
            payload["cause"] = cause
        }
        if let error, !error.isEmpty {
            payload["error"] = error
        }
        _ = try await client.stepFunctionsRequest(action: "StopExecution", payload: payload)
    }

    // MARK: - Execution History

    struct HistoryResult {
        let events: [StepFunctionsHistoryEvent]
        let nextToken: String?
    }

    func getExecutionHistory(arn: String, nextToken: String? = nil, maxResults: Int = 50) async throws -> HistoryResult {
        var payload: [String: Any] = [
            "executionArn": arn,
            "maxResults": maxResults,
        ]
        if let token = nextToken {
            payload["nextToken"] = token
        }
        let data = try await client.stepFunctionsRequest(action: "GetExecutionHistory", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = json["events"] as? [[String: Any]] else {
            return HistoryResult(events: [], nextToken: nil)
        }
        return HistoryResult(
            events: events.map { StepFunctionsHistoryEvent(from: $0) },
            nextToken: json["nextToken"] as? String
        )
    }
}
