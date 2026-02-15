import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("Step Functions Models")
struct StepFunctionsModelTests {

    // MARK: - StateMachineSummary.truncatedName

    @Test("truncatedName truncates long names")
    func truncatedNameLong() {
        let sm = StateMachineSummary(name: "very-long-state-machine-name-that-exceeds-30-chars")
        #expect(sm.truncatedName.hasSuffix("..."))
        #expect(sm.truncatedName.count == 30)
    }

    @Test("truncatedName returns short names as-is")
    func truncatedNameShort() {
        let sm = StateMachineSummary(name: "my-sm")
        #expect(sm.truncatedName == "my-sm")
    }

    // MARK: - StateMachineSummary.init(from:)

    @Test("parses from dict")
    func summaryInit() {
        let sm = StateMachineSummary(from: [
            "name": "my-state-machine",
            "stateMachineArn": "arn:aws:states:us-east-1:000:stateMachine:my-state-machine",
            "type": "EXPRESS",
            "creationDate": 1700000000.0,
        ])
        #expect(sm.name == "my-state-machine")
        #expect(sm.type == "EXPRESS")
        #expect(sm.creationDate != nil)
    }

    // MARK: - StateMachineDetail.prettyDefinition

    @Test("prettyDefinition formats JSON")
    func prettyDefinition() {
        let detail = StateMachineDetail(from: [
            "name": "test",
            "stateMachineArn": "arn:test",
            "definition": "{\"StartAt\":\"Hello\",\"States\":{\"Hello\":{\"Type\":\"Pass\",\"End\":true}}}",
            "roleArn": "arn:role",
        ])
        #expect(detail.prettyDefinition.contains("StartAt"))
        #expect(detail.prettyDefinition.contains("  ")) // indented
    }

    @Test("prettyDefinition returns raw for invalid JSON")
    func prettyDefinitionInvalid() {
        let detail = StateMachineDetail(from: [
            "name": "test",
            "stateMachineArn": "arn:test",
            "definition": "not json",
        ])
        #expect(detail.prettyDefinition == "not json")
    }

    // MARK: - StepFunctionsExecution.displayName

    @Test("displayName returns name when set")
    func displayNameWithName() {
        let exec = StepFunctionsExecution(
            executionArn: "arn:aws:states:us-east-1:000:execution:sm:my-exec",
            name: "my-exec"
        )
        #expect(exec.displayName == "my-exec")
    }

    @Test("displayName extracts from ARN when name is empty")
    func displayNameFromArn() {
        let exec = StepFunctionsExecution(
            executionArn: "arn:aws:states:us-east-1:000:execution:sm:exec-123"
        )
        #expect(exec.displayName == "exec-123")
    }

    // MARK: - StepFunctionsExecution.duration

    @Test("duration shows seconds for short runs")
    func durationSeconds() {
        let start = Date()
        let exec = StepFunctionsExecution(
            startDate: start,
            stopDate: start.addingTimeInterval(30)
        )
        #expect(exec.duration == "30s")
    }

    @Test("duration shows minutes and seconds")
    func durationMinutes() {
        let start = Date()
        let exec = StepFunctionsExecution(
            startDate: start,
            stopDate: start.addingTimeInterval(125)
        )
        #expect(exec.duration == "2m 5s")
    }

    @Test("duration shows hours and minutes")
    func durationHours() {
        let start = Date()
        let exec = StepFunctionsExecution(
            startDate: start,
            stopDate: start.addingTimeInterval(7500)
        )
        #expect(exec.duration == "2h 5m")
    }

    @Test("duration shows <1s for sub-second runs")
    func durationSubSecond() {
        let start = Date()
        let exec = StepFunctionsExecution(
            startDate: start,
            stopDate: start.addingTimeInterval(0.5)
        )
        #expect(exec.duration == "<1s")
    }

    @Test("duration nil when no start date")
    func durationNil() {
        let exec = StepFunctionsExecution()
        #expect(exec.duration == nil)
    }

    // MARK: - StepFunctionsHistoryEvent.badgeColor

    @Test("badgeColor maps event types correctly")
    func historyBadgeColor() {
        let succeeded = StepFunctionsHistoryEvent(from: ["type": "TaskSucceeded", "id": 1, "previousEventId": 0])
        #expect(succeeded.badgeColor == "green")

        let failed = StepFunctionsHistoryEvent(from: ["type": "ExecutionFailed", "id": 2, "previousEventId": 1])
        #expect(failed.badgeColor == "red")

        let started = StepFunctionsHistoryEvent(from: ["type": "ExecutionStarted", "id": 3, "previousEventId": 0])
        #expect(started.badgeColor == "cyan")

        let scheduled = StepFunctionsHistoryEvent(from: ["type": "TaskScheduled", "id": 4, "previousEventId": 3])
        #expect(scheduled.badgeColor == "blue")

        let unknown = StepFunctionsHistoryEvent(from: ["type": "UnknownType", "id": 5, "previousEventId": 4])
        #expect(unknown.badgeColor == "gray")
    }

    // MARK: - CLI

    @Test("describeStateMachineCLI generates valid command")
    func describeStateMachineCLI() {
        let sm = StateMachineSummary(stateMachineArn: "arn:aws:states:us-east-1:000:stateMachine:my-sm")
        let cli = sm.describeStateMachineCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws stepfunctions describe-state-machine"))
        #expect(cli.contains("arn:aws:states:us-east-1:000:stateMachine:my-sm"))
    }

    @Test("describeExecutionCLI generates valid command")
    func describeExecutionCLI() {
        let exec = StepFunctionsExecution(executionArn: "arn:aws:states:us-east-1:000:execution:sm:exec-1")
        let cli = exec.describeExecutionCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws stepfunctions describe-execution"))
    }
}
