import Foundation

struct LambdaFunction: Identifiable, Hashable {
    let functionName: String
    let functionArn: String
    let runtime: String
    let handler: String
    let role: String
    let description: String
    let timeout: Int
    let memorySize: Int
    let codeSize: Int64
    let codeSha256: String
    let lastModified: String
    let state: String
    let version: String
    let environment: [String: String]
    let layers: [String]

    var id: String { functionName }

    var isActive: Bool { state == "Active" || state.isEmpty }

    var formattedCodeSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: codeSize)
    }

    var runtimeBadgeColor: RuntimeColor {
        if runtime.hasPrefix("python") { return .python }
        if runtime.hasPrefix("nodejs") { return .nodejs }
        if runtime.hasPrefix("java") { return .java }
        if runtime.hasPrefix("dotnet") { return .dotnet }
        if runtime.hasPrefix("go") || runtime == "provided.al2023" || runtime == "provided.al2" { return .custom }
        if runtime.hasPrefix("ruby") { return .ruby }
        return .custom
    }

    enum RuntimeColor {
        case python, nodejs, java, dotnet, custom, ruby

        var color: String {
            switch self {
            case .python: "blue"
            case .nodejs: "green"
            case .java: "orange"
            case .dotnet: "purple"
            case .ruby: "red"
            case .custom: "gray"
            }
        }
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func getFunctionCLI(endpointUrl: String, region: String) -> String {
        [
            "aws lambda get-function \\",
            "  --function-name '\(Self.shellEscape(functionName))' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    func invokeCLI(endpointUrl: String, region: String) -> String {
        [
            "aws lambda invoke \\",
            "  --function-name '\(Self.shellEscape(functionName))' \\",
            "  --payload '{}' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)' \\",
            "  /dev/stdout",
        ].joined(separator: "\n")
    }

    static func listFunctionsCLI(endpointUrl: String, region: String) -> String {
        [
            "aws lambda list-functions \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        functionName = dict["FunctionName"] as? String ?? ""
        functionArn = dict["FunctionArn"] as? String ?? ""
        runtime = dict["Runtime"] as? String ?? ""
        handler = dict["Handler"] as? String ?? ""
        role = dict["Role"] as? String ?? ""
        description = dict["Description"] as? String ?? ""
        timeout = dict["Timeout"] as? Int ?? 3
        memorySize = dict["MemorySize"] as? Int ?? 128
        codeSize = dict["CodeSize"] as? Int64 ?? (dict["CodeSize"] as? Int).map(Int64.init) ?? 0
        codeSha256 = dict["CodeSha256"] as? String ?? ""
        lastModified = dict["LastModified"] as? String ?? ""
        state = dict["State"] as? String ?? ""
        version = dict["Version"] as? String ?? ""

        if let envDict = dict["Environment"] as? [String: Any],
           let vars = envDict["Variables"] as? [String: String] {
            environment = vars
        } else {
            environment = [:]
        }

        if let layerList = dict["Layers"] as? [[String: Any]] {
            layers = layerList.compactMap { $0["Arn"] as? String }
        } else {
            layers = []
        }
    }
}

struct LambdaInvocationResult {
    let statusCode: Int
    let payload: String
    let functionError: String?
    let logResult: String?

    var isError: Bool { functionError != nil }

    var isJSON: Bool {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    var prettyPrinted: String? {
        guard isJSON,
              let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    var displayPayload: String {
        prettyPrinted ?? payload
    }
}
