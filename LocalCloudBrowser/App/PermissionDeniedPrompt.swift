import Foundation

/// Describes a permission-denied event surfaced from a real AWS request.
/// Drives the `PermissionHelperView` sheet.
struct PermissionDeniedPrompt: Identifiable, Equatable {
    let id = UUID()
    let serviceKey: String          // SigV4 service name (e.g., "iam", "sqs")
    let deniedAction: String?       // e.g., "iam:ListUsers", parsed from error message
    let rawMessage: String          // full AWS error message, shown in disclosure
    let isPermissionsBoundary: Bool // true when error indicates a permissions boundary is capping access

    /// Parses an AWS-style denied action out of the error message.
    /// Messages look like: "User: arn:... is not authorized to perform: iam:ListUsers on resource: ..."
    static func extractDeniedAction(from message: String) -> String? {
        guard let range = message.range(of: "perform: ") else { return nil }
        let afterPerform = message[range.upperBound...]
        let action = afterPerform.prefix { !$0.isWhitespace }
        let trimmed = action.trimmingCharacters(in: CharacterSet(charactersIn: ","))
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Returns true when the error message indicates a permissions boundary caused the deny.
    static func detectBoundary(in message: String) -> Bool {
        message.lowercased().contains("permissions boundary")
    }
}
