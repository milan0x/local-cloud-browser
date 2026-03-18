import Foundation

enum StepFunctionsTab: String, CaseIterable {
    case definition = "Definition"
    case executions = "Executions"
}

struct StateMachineSummary: Identifiable, Hashable {
    let name: String
    let stateMachineArn: String
    let type: String
    let creationDate: Date?

    var id: String { stateMachineArn }

    var truncatedName: String {
        if name.count > 30 {
            return String(name.prefix(27)) + "..."
        }
        return name
    }

    init(name: String = "", stateMachineArn: String = "", type: String = "STANDARD", creationDate: Date? = nil) {
        self.name = name
        self.stateMachineArn = stateMachineArn
        self.type = type
        self.creationDate = creationDate
    }

    init(from dict: [String: Any]) {
        name = dict["name"] as? String ?? ""
        stateMachineArn = dict["stateMachineArn"] as? String ?? ""
        type = dict["type"] as? String ?? "STANDARD"
        creationDate = DateFormatters.parseDateValue(dict["creationDate"])
    }

    func describeStateMachineCLI(endpointUrl: String, region: String) -> String {
        [
            "aws stepfunctions describe-state-machine \\",
            "  --state-machine-arn '\(stateMachineArn.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listStateMachinesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws stepfunctions list-state-machines \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct StateMachineDetail: Identifiable, Hashable {
    let name: String
    let stateMachineArn: String
    let definition: String
    let roleArn: String
    let type: String
    let status: String
    let creationDate: Date?

    var id: String { stateMachineArn }

    init(from dict: [String: Any]) {
        name = dict["name"] as? String ?? ""
        stateMachineArn = dict["stateMachineArn"] as? String ?? ""
        definition = dict["definition"] as? String ?? ""
        roleArn = dict["roleArn"] as? String ?? ""
        type = dict["type"] as? String ?? "STANDARD"
        status = dict["status"] as? String ?? "ACTIVE"
        creationDate = DateFormatters.parseDateValue(dict["creationDate"])
    }

    var prettyDefinition: String {
        guard let data = definition.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return definition
        }
        return result
    }
}

struct StepFunctionsExecution: Identifiable, Hashable {
    let executionArn: String
    let name: String
    let stateMachineArn: String
    let status: String
    let startDate: Date?
    let stopDate: Date?

    var id: String { executionArn }

    var displayName: String {
        if name.isEmpty {
            let components = executionArn.split(separator: ":")
            return components.last.map(String.init) ?? executionArn
        }
        return name
    }

    var duration: String? {
        guard let start = startDate else { return nil }
        let end = stopDate ?? Date()
        let interval = end.timeIntervalSince(start)
        if interval < 1 {
            return "<1s"
        } else if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            let mins = Int(interval) / 60
            let secs = Int(interval) % 60
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(interval) / 3600
            let mins = (Int(interval) % 3600) / 60
            return "\(hours)h \(mins)m"
        }
    }

    init(executionArn: String = "", name: String = "", stateMachineArn: String = "",
         status: String = "RUNNING", startDate: Date? = nil, stopDate: Date? = nil) {
        self.executionArn = executionArn
        self.name = name
        self.stateMachineArn = stateMachineArn
        self.status = status
        self.startDate = startDate
        self.stopDate = stopDate
    }

    init(from dict: [String: Any]) {
        executionArn = dict["executionArn"] as? String ?? ""
        name = dict["name"] as? String ?? ""
        stateMachineArn = dict["stateMachineArn"] as? String ?? ""
        status = dict["status"] as? String ?? "RUNNING"
        startDate = DateFormatters.parseDateValue(dict["startDate"])
        stopDate = DateFormatters.parseDateValue(dict["stopDate"])
    }

    func describeExecutionCLI(endpointUrl: String, region: String) -> String {
        [
            "aws stepfunctions describe-execution \\",
            "  --execution-arn '\(executionArn.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct StepFunctionsExecutionDetail: Identifiable, Hashable {
    let executionArn: String
    let name: String
    let stateMachineArn: String
    let status: String
    let startDate: Date?
    let stopDate: Date?
    let input: String
    let output: String

    var id: String { executionArn }

    init(from dict: [String: Any]) {
        executionArn = dict["executionArn"] as? String ?? ""
        name = dict["name"] as? String ?? ""
        stateMachineArn = dict["stateMachineArn"] as? String ?? ""
        status = dict["status"] as? String ?? "RUNNING"
        startDate = DateFormatters.parseDateValue(dict["startDate"])
        stopDate = DateFormatters.parseDateValue(dict["stopDate"])
        input = dict["input"] as? String ?? ""
        output = dict["output"] as? String ?? ""
    }

    var prettyInput: String { Self.prettyJSON(input) }
    var prettyOutput: String { Self.prettyJSON(output) }

    var duration: String? {
        guard let start = startDate else { return nil }
        let end = stopDate ?? Date()
        let interval = end.timeIntervalSince(start)
        if interval < 1 {
            return "<1s"
        } else if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            let mins = Int(interval) / 60
            let secs = Int(interval) % 60
            return "\(mins)m \(secs)s"
        } else {
            let hours = Int(interval) / 3600
            let mins = (Int(interval) % 3600) / 60
            return "\(hours)h \(mins)m"
        }
    }

    private static func prettyJSON(_ str: String) -> String {
        guard !str.isEmpty,
              let data = str.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return str
        }
        return result
    }
}

struct StepFunctionsHistoryEvent: Identifiable, Hashable {
    let id: Int
    let type: String
    let timestamp: Date?
    let previousEventId: Int

    init(from dict: [String: Any]) {
        id = dict["id"] as? Int ?? 0
        type = dict["type"] as? String ?? ""
        previousEventId = dict["previousEventId"] as? Int ?? 0
        if let date = DateFormatters.parseDateValue(dict["timestamp"]) {
            timestamp = date
        } else {
            timestamp = nil
        }
    }

    var badgeColor: String {
        let t = type.lowercased()
        if t.contains("succeeded") { return "green" }
        if t.contains("failed") || t.contains("aborted") { return "red" }
        if t.contains("started") || t.contains("entered") { return "cyan" }
        if t.contains("scheduled") { return "blue" }
        if t.contains("wait") { return "orange" }
        if t.contains("choice") { return "purple" }
        if t.contains("parallel") { return "indigo" }
        return "gray"
    }
}
