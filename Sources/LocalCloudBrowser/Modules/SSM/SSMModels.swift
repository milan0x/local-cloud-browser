import Foundation

struct SSMParameter: Identifiable, Hashable {
    let name: String
    let type: String
    let lastModifiedDate: Date?
    let version: Int
    let description: String?
    let tier: String?
    let dataType: String?
    let arn: String?

    var id: String { name }

    var displayType: String { type }

    var isSecureString: Bool { type == "SecureString" }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func getParameterCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ssm get-parameter \\",
            "  --name '\(Self.shellEscape(name))' \\",
            isSecureString ? "  --with-decryption \\" : nil,
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].compactMap { $0 }.joined(separator: "\n")
    }

    func describeParametersCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ssm describe-parameters \\",
            "  --filters 'Key=Name,Values=\(Self.shellEscape(name))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        name = dict["Name"] as? String ?? ""
        type = dict["Type"] as? String ?? "String"
        version = dict["Version"] as? Int ?? 1
        description = dict["Description"] as? String
        tier = dict["Tier"] as? String
        dataType = dict["DataType"] as? String
        arn = dict["ARN"] as? String

        if let ts = dict["LastModifiedDate"] as? Double {
            lastModifiedDate = Date(timeIntervalSince1970: ts)
        } else {
            lastModifiedDate = nil
        }
    }
}

struct SSMParameterValue {
    let name: String
    let type: String
    let value: String
    let version: Int
    let lastModifiedDate: Date?
    let arn: String?

    var isSecureString: Bool { type == "SecureString" }

    var isJSON: Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    var prettyPrinted: String? {
        guard isJSON,
              let data = value.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    var displayValue: String {
        prettyPrinted ?? value
    }

    init(from dict: [String: Any]) {
        let param = dict["Parameter"] as? [String: Any] ?? dict
        name = param["Name"] as? String ?? ""
        type = param["Type"] as? String ?? "String"
        value = param["Value"] as? String ?? ""
        version = param["Version"] as? Int ?? 1
        arn = param["ARN"] as? String

        if let ts = param["LastModifiedDate"] as? Double {
            lastModifiedDate = Date(timeIntervalSince1970: ts)
        } else {
            lastModifiedDate = nil
        }
    }
}
