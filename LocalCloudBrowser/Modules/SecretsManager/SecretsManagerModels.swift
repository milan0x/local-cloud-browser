import Foundation

struct Secret: Identifiable, Hashable {
    let arn: String
    let name: String
    let description: String?
    let createdDate: Date?
    let lastChangedDate: Date?
    let lastAccessedDate: Date?
    let tags: [String: String]

    var id: String { arn }

    func getSecretValueCLI(endpointUrl: String, region: String) -> String {
        [
            "aws secretsmanager get-secret-value \\",
            "  --secret-id '\(name.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'"
        ].joined(separator: "\n")
    }

    func describeSecretCLI(endpointUrl: String, region: String) -> String {
        [
            "aws secretsmanager describe-secret \\",
            "  --secret-id '\(name.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'"
        ].joined(separator: "\n")
    }

    init(from dict: [String: Any]) {
        arn = dict["ARN"] as? String ?? ""
        name = dict["Name"] as? String ?? ""
        description = dict["Description"] as? String
        tags = {
            guard let tagList = dict["Tags"] as? [[String: String]] else { return [:] }
            var result: [String: String] = [:]
            for tag in tagList {
                if let key = tag["Key"], let value = tag["Value"] {
                    result[key] = value
                }
            }
            return result
        }()

        if let ts = dict["CreatedDate"] as? Double {
            createdDate = Date(timeIntervalSince1970: ts)
        } else {
            createdDate = nil
        }
        if let ts = dict["LastChangedDate"] as? Double {
            lastChangedDate = Date(timeIntervalSince1970: ts)
        } else {
            lastChangedDate = nil
        }
        if let ts = dict["LastAccessedDate"] as? Double {
            lastAccessedDate = Date(timeIntervalSince1970: ts)
        } else {
            lastAccessedDate = nil
        }
    }
}

struct SecretDetail {
    let arn: String
    let name: String
    let description: String?
    let createdDate: Date?
    let lastChangedDate: Date?
    let lastAccessedDate: Date?
    let rotationEnabled: Bool
    let tags: [String: String]
    let versionIdsToStages: [String: [String]]

    init(from dict: [String: Any]) {
        arn = dict["ARN"] as? String ?? ""
        name = dict["Name"] as? String ?? ""
        description = dict["Description"] as? String
        rotationEnabled = dict["RotationEnabled"] as? Bool ?? false
        tags = {
            guard let tagList = dict["Tags"] as? [[String: String]] else { return [:] }
            var result: [String: String] = [:]
            for tag in tagList {
                if let key = tag["Key"], let value = tag["Value"] {
                    result[key] = value
                }
            }
            return result
        }()
        versionIdsToStages = {
            guard let versions = dict["VersionIdsToStages"] as? [String: [String]] else { return [:] }
            return versions
        }()

        if let ts = dict["CreatedDate"] as? Double {
            createdDate = Date(timeIntervalSince1970: ts)
        } else {
            createdDate = nil
        }
        if let ts = dict["LastChangedDate"] as? Double {
            lastChangedDate = Date(timeIntervalSince1970: ts)
        } else {
            lastChangedDate = nil
        }
        if let ts = dict["LastAccessedDate"] as? Double {
            lastAccessedDate = Date(timeIntervalSince1970: ts)
        } else {
            lastAccessedDate = nil
        }
    }
}

struct SecretValue {
    let arn: String
    let name: String
    let secretString: String?
    let secretBinary: String?
    let versionId: String
    let versionStages: [String]
    let createdDate: Date?

    var isJSON: Bool {
        guard let s = secretString?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return s.hasPrefix("{") || s.hasPrefix("[")
    }

    var prettyPrinted: String? {
        guard isJSON, let s = secretString,
              let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return nil
        }
        return result
    }

    var displayValue: String {
        prettyPrinted ?? secretString ?? secretBinary ?? ""
    }

    init(from dict: [String: Any]) {
        arn = dict["ARN"] as? String ?? ""
        name = dict["Name"] as? String ?? ""
        secretString = dict["SecretString"] as? String
        secretBinary = dict["SecretBinary"] as? String
        versionId = dict["VersionId"] as? String ?? ""
        versionStages = dict["VersionStages"] as? [String] ?? []

        if let ts = dict["CreatedDate"] as? Double {
            createdDate = Date(timeIntervalSince1970: ts)
        } else {
            createdDate = nil
        }
    }
}
