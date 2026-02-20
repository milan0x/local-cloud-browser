import Testing
import Foundation
@testable import LocalCloudBrowser

@Suite("Lambda Models")
struct LambdaModelTests {

    // MARK: - Helpers

    private func makeFunction(
        name: String = "my-func",
        runtime: String = "python3.12",
        state: String = "Active",
        codeSize: Int64 = 1024
    ) -> LambdaFunction {
        LambdaFunction(from: [
            "FunctionName": name,
            "FunctionArn": "arn:aws:lambda:us-east-1:000:\(name)",
            "Runtime": runtime,
            "Handler": "index.handler",
            "Role": "arn:aws:iam::000:role/lambda-role",
            "Description": "test function",
            "Timeout": 30,
            "MemorySize": 256,
            "CodeSize": codeSize,
            "CodeSha256": "abc123",
            "LastModified": "2024-01-15",
            "State": state,
            "Version": "$LATEST",
        ])
    }

    // MARK: - isActive

    @Test("isActive when state is Active")
    func isActiveTrue() {
        #expect(makeFunction(state: "Active").isActive == true)
    }

    @Test("isActive when state is empty")
    func isActiveEmpty() {
        #expect(makeFunction(state: "").isActive == true)
    }

    @Test("isActive false for other states")
    func isActiveFalse() {
        #expect(makeFunction(state: "Inactive").isActive == false)
        #expect(makeFunction(state: "Failed").isActive == false)
    }

    // MARK: - runtimeBadgeColor

    @Test("Python runtime maps to python color")
    func runtimePython() {
        #expect(makeFunction(runtime: "python3.12").runtimeBadgeColor == .python)
        #expect(makeFunction(runtime: "python3.9").runtimeBadgeColor == .python)
    }

    @Test("Node.js runtime maps to nodejs color")
    func runtimeNodejs() {
        #expect(makeFunction(runtime: "nodejs20.x").runtimeBadgeColor == .nodejs)
        #expect(makeFunction(runtime: "nodejs18.x").runtimeBadgeColor == .nodejs)
    }

    @Test("Java runtime maps to java color")
    func runtimeJava() {
        #expect(makeFunction(runtime: "java21").runtimeBadgeColor == .java)
        #expect(makeFunction(runtime: "java17").runtimeBadgeColor == .java)
    }

    @Test("Dotnet runtime maps to dotnet color")
    func runtimeDotnet() {
        #expect(makeFunction(runtime: "dotnet8").runtimeBadgeColor == .dotnet)
    }

    @Test("Ruby runtime maps to ruby color")
    func runtimeRuby() {
        #expect(makeFunction(runtime: "ruby3.3").runtimeBadgeColor == .ruby)
    }

    @Test("Go and provided runtimes map to custom color")
    func runtimeCustom() {
        #expect(makeFunction(runtime: "go1.x").runtimeBadgeColor == .custom)
        #expect(makeFunction(runtime: "provided.al2023").runtimeBadgeColor == .custom)
        #expect(makeFunction(runtime: "provided.al2").runtimeBadgeColor == .custom)
    }

    @Test("Unknown runtime maps to custom color")
    func runtimeUnknown() {
        #expect(makeFunction(runtime: "unknown").runtimeBadgeColor == .custom)
    }

    // MARK: - formattedCodeSize

    @Test("formattedCodeSize formats bytes")
    func formattedCodeSize() {
        let f = makeFunction(codeSize: 1024)
        #expect(!f.formattedCodeSize.isEmpty)
    }

    // MARK: - init(from:)

    @Test("Parses environment variables")
    func parseEnvironment() {
        let dict: [String: Any] = [
            "FunctionName": "test",
            "Environment": ["Variables": ["KEY": "value", "OTHER": "123"]],
        ]
        let f = LambdaFunction(from: dict)
        #expect(f.environment["KEY"] == "value")
        #expect(f.environment["OTHER"] == "123")
    }

    @Test("Parses layers")
    func parseLayers() {
        let dict: [String: Any] = [
            "FunctionName": "test",
            "Layers": [
                ["Arn": "arn:aws:lambda:us-east-1:000:layer:my-layer:1"],
                ["Arn": "arn:aws:lambda:us-east-1:000:layer:other:2"],
            ],
        ]
        let f = LambdaFunction(from: dict)
        #expect(f.layers.count == 2)
        #expect(f.layers[0].contains("my-layer"))
    }

    @Test("Defaults for missing fields")
    func parseDefaults() {
        let f = LambdaFunction(from: [:])
        #expect(f.functionName == "")
        #expect(f.timeout == 3)
        #expect(f.memorySize == 128)
        #expect(f.codeSize == 0)
        #expect(f.environment.isEmpty)
        #expect(f.layers.isEmpty)
    }

    // MARK: - CLI

    @Test("getFunctionCLI generates valid command")
    func getFunctionCLI() {
        let f = makeFunction(name: "my-func")
        let cli = f.getFunctionCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws lambda get-function"))
        #expect(cli.contains("my-func"))
    }

    @Test("invokeCLI generates valid command")
    func invokeCLI() {
        let f = makeFunction(name: "my-func")
        let cli = f.invokeCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws lambda invoke"))
        #expect(cli.contains("--payload"))
        #expect(cli.contains("/dev/stdout"))
    }

    @Test("listFunctionsCLI generates valid command")
    func listFunctionsCLI() {
        let cli = LambdaFunction.listFunctionsCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws lambda list-functions"))
    }

    // MARK: - LambdaInvocationResult

    @Test("isError when functionError is set")
    func invocationIsError() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "{}", functionError: "Unhandled", logResult: nil)
        #expect(result.isError == true)
    }

    @Test("isError false when functionError is nil")
    func invocationNotError() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "{}", functionError: nil, logResult: nil)
        #expect(result.isError == false)
    }

    @Test("isJSON detects JSON payload")
    func invocationIsJSON() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "{\"key\": \"value\"}", functionError: nil, logResult: nil)
        #expect(result.isJSON == true)
    }

    @Test("isJSON detects array payload")
    func invocationIsJSONArray() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "[1, 2]", functionError: nil, logResult: nil)
        #expect(result.isJSON == true)
    }

    @Test("isJSON false for text payload")
    func invocationNotJSON() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "hello world", functionError: nil, logResult: nil)
        #expect(result.isJSON == false)
    }

    @Test("prettyPrinted formats JSON")
    func invocationPrettyPrinted() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "{\"a\":1}", functionError: nil, logResult: nil)
        #expect(result.prettyPrinted != nil)
        #expect(result.prettyPrinted!.contains("\"a\" : 1"))
    }

    @Test("prettyPrinted nil for non-JSON")
    func invocationPrettyPrintedNil() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "plain text", functionError: nil, logResult: nil)
        #expect(result.prettyPrinted == nil)
    }

    @Test("displayPayload falls back to raw")
    func displayPayload() {
        let result = LambdaInvocationResult(statusCode: 200, payload: "raw text", functionError: nil, logResult: nil)
        #expect(result.displayPayload == "raw text")
    }
}
