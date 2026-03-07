import Foundation

final class EventBridgeSchedulerService: BaseService {
    // MARK: - Schedule Groups

    func listScheduleGroups() async throws -> [SchedulerScheduleGroup] {
        var allGroups: [SchedulerScheduleGroup] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.schedulerRequest(action: "ListScheduleGroups", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let groups = json["ScheduleGroups"] as? [[String: Any]] {
                allGroups.append(contentsOf: groups.map { SchedulerScheduleGroup(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allGroups
    }

    func createScheduleGroup(name: String) async throws {
        _ = try await client.schedulerRequest(
            action: "CreateScheduleGroup",
            payload: ["Name": name]
        )
    }

    func deleteScheduleGroup(name: String) async throws {
        _ = try await client.schedulerRequest(
            action: "DeleteScheduleGroup",
            payload: ["Name": name]
        )
    }

    // MARK: - Schedules

    func listSchedules(groupName: String) async throws -> [SchedulerSchedule] {
        var allSchedules: [SchedulerSchedule] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = ["GroupName": groupName]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.schedulerRequest(action: "ListSchedules", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let schedules = json["Schedules"] as? [[String: Any]] {
                allSchedules.append(contentsOf: schedules.map { SchedulerSchedule(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allSchedules
    }

    func getSchedule(name: String, groupName: String) async throws -> SchedulerSchedule {
        let data = try await client.schedulerRequest(
            action: "GetSchedule",
            payload: ["Name": name, "GroupName": groupName]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return SchedulerSchedule(from: json)
    }

    func createSchedule(
        name: String,
        groupName: String,
        expression: String,
        timezone: String,
        description: String?,
        state: String,
        targetArn: String,
        targetRoleArn: String,
        targetInput: String?,
        flexibleTimeWindowMode: String,
        flexibleTimeWindowMaxMinutes: Int?
    ) async throws {
        var target: [String: Any] = [
            "Arn": targetArn,
            "RoleArn": targetRoleArn,
        ]
        if let input = targetInput, !input.isEmpty {
            target["Input"] = input
        }

        var flexWindow: [String: Any] = ["Mode": flexibleTimeWindowMode]
        if flexibleTimeWindowMode == "FLEXIBLE", let minutes = flexibleTimeWindowMaxMinutes {
            flexWindow["MaximumWindowInMinutes"] = minutes
        }

        var payload: [String: Any] = [
            "Name": name,
            "GroupName": groupName,
            "ScheduleExpression": expression,
            "ScheduleExpressionTimezone": timezone,
            "State": state,
            "Target": target,
            "FlexibleTimeWindow": flexWindow,
        ]
        if let desc = description, !desc.isEmpty {
            payload["Description"] = desc
        }

        _ = try await client.schedulerRequest(action: "CreateSchedule", payload: payload)
    }

    func updateScheduleState(name: String, groupName: String, enable: Bool, schedule: SchedulerSchedule) async throws {
        // UpdateSchedule requires all fields — rebuild from existing schedule
        var target: [String: Any] = [:]
        if let arn = schedule.targetArn {
            target["Arn"] = arn
        }
        if let roleArn = schedule.targetRoleArn {
            target["RoleArn"] = roleArn
        }
        if let input = schedule.targetInput {
            target["Input"] = input
        }

        var flexWindow: [String: Any] = ["Mode": schedule.flexibleTimeWindowMode ?? "OFF"]
        if let minutes = schedule.flexibleTimeWindowMaximumWindowInMinutes {
            flexWindow["MaximumWindowInMinutes"] = minutes
        }

        var payload: [String: Any] = [
            "Name": name,
            "GroupName": groupName,
            "State": enable ? "ENABLED" : "DISABLED",
            "Target": target,
            "FlexibleTimeWindow": flexWindow,
        ]
        if let expr = schedule.scheduleExpression {
            payload["ScheduleExpression"] = expr
        }
        if let tz = schedule.scheduleExpressionTimezone {
            payload["ScheduleExpressionTimezone"] = tz
        }
        if let desc = schedule.description {
            payload["Description"] = desc
        }

        _ = try await client.schedulerRequest(action: "UpdateSchedule", payload: payload)
    }

    func deleteSchedule(name: String, groupName: String) async throws {
        _ = try await client.schedulerRequest(
            action: "DeleteSchedule",
            payload: ["Name": name, "GroupName": groupName]
        )
    }
}
