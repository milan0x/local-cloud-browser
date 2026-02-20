import Foundation

struct KMSKey: Identifiable, Hashable {
    let keyId: String
    let arn: String
    let description: String
    let enabled: Bool
    let keyState: String
    let keyUsage: String
    let keySpec: String
    let creationDate: Date?
    let keyManager: String
    let origin: String

    var id: String { keyId }

    var truncatedId: String {
        if keyId.count > 8 {
            return String(keyId.prefix(8)) + "..."
        }
        return keyId
    }

    var stateBadgeColor: String {
        switch keyState {
        case "Enabled": return "green"
        case "Disabled": return "orange"
        case "PendingDeletion": return "red"
        default: return "gray"
        }
    }

    init(keyId: String = "", arn: String = "", description: String = "",
         enabled: Bool = true, keyState: String = "Enabled",
         keyUsage: String = "ENCRYPT_DECRYPT", keySpec: String = "SYMMETRIC_DEFAULT",
         creationDate: Date? = nil, keyManager: String = "CUSTOMER", origin: String = "AWS_KMS") {
        self.keyId = keyId
        self.arn = arn
        self.description = description
        self.enabled = enabled
        self.keyState = keyState
        self.keyUsage = keyUsage
        self.keySpec = keySpec
        self.creationDate = creationDate
        self.keyManager = keyManager
        self.origin = origin
    }

    init(from dict: [String: Any]) {
        keyId = dict["KeyId"] as? String ?? ""
        arn = dict["Arn"] as? String ?? ""
        description = dict["Description"] as? String ?? ""
        enabled = dict["Enabled"] as? Bool ?? true
        keyState = dict["KeyState"] as? String ?? "Enabled"
        keyUsage = dict["KeyUsage"] as? String ?? "ENCRYPT_DECRYPT"
        keySpec = dict["KeySpec"] as? String ?? "SYMMETRIC_DEFAULT"
        keyManager = dict["KeyManager"] as? String ?? "CUSTOMER"
        origin = dict["Origin"] as? String ?? "AWS_KMS"

        if let ts = dict["CreationDate"] as? Double {
            creationDate = Date(timeIntervalSince1970: ts)
        } else {
            creationDate = nil
        }
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeKeyCLI(endpointUrl: String, region: String) -> String {
        [
            "aws kms describe-key \\",
            "  --key-id '\(Self.shellEscape(keyId))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }

    static func listKeysCLI(endpointUrl: String, region: String) -> String {
        [
            "aws kms list-keys \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)"
        ].joined(separator: "\n")
    }
}

struct KMSAlias: Identifiable, Hashable {
    let aliasName: String
    let aliasArn: String
    let targetKeyId: String

    var id: String { aliasName }

    init(from dict: [String: Any]) {
        aliasName = dict["AliasName"] as? String ?? ""
        aliasArn = dict["AliasArn"] as? String ?? ""
        targetKeyId = dict["TargetKeyId"] as? String ?? ""
    }
}
