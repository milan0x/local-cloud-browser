import Foundation

struct SESIdentity: Identifiable, Hashable {
    let identity: String

    var id: String { identity }

    var isEmail: Bool {
        identity.contains("@")
    }

    var typeBadge: String {
        isEmail ? "Email" : "Domain"
    }

    /// Shell-escape a string for use inside single quotes: replace `'` with `'\''`
    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func deleteIdentityCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ses delete-identity \\",
            "  --identity '\(Self.shellEscape(identity))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listIdentitiesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ses list-identities \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func sendEmailCLI(endpointUrl: String, region: String) -> String {
        [
            "aws ses send-email \\",
            "  --from '\(Self.shellEscape(identity))' \\",
            "  --destination 'ToAddresses=recipient@example.com' \\",
            "  --message 'Subject={Data=Test},Body={Text={Data=Hello}}' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}

struct SESSentEmailDestination {
    let toAddresses: [String]
    let ccAddresses: [String]
    let bccAddresses: [String]
}

struct SESSentEmailBody {
    let textData: String?
    let htmlData: String?
}

struct SESSentEmail: Identifiable {
    let id: String
    let source: String
    let destination: SESSentEmailDestination
    let subject: String
    let body: SESSentEmailBody
    let timestamp: Date?

    var recipientSummary: String {
        let all = destination.toAddresses + destination.ccAddresses + destination.bccAddresses
        guard !all.isEmpty else { return "—" }
        if all.count == 1 { return all[0] }
        return "\(all[0]) +\(all.count - 1)"
    }

    var formattedTimestamp: String {
        guard let timestamp else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    init(from dict: [String: Any]) {
        self.id = dict["Id"] as? String ?? UUID().uuidString
        self.source = dict["Source"] as? String ?? ""

        // Parse destination
        let destDict = dict["Destination"] as? [String: Any] ?? [:]
        self.destination = SESSentEmailDestination(
            toAddresses: destDict["ToAddresses"] as? [String] ?? [],
            ccAddresses: destDict["CcAddresses"] as? [String] ?? [],
            bccAddresses: destDict["BccAddresses"] as? [String] ?? []
        )

        // Parse subject from either Body.subject or top-level Subject
        if let bodyDict = dict["Body"] as? [String: Any] {
            // Endpoint may put subject inside Body
            self.subject = bodyDict["subject"] as? String
                ?? (dict["Subject"] as? String ?? "")
        } else {
            self.subject = dict["Subject"] as? String ?? ""
        }

        // Parse body — handle both flat and nested formats
        if let bodyDict = dict["Body"] as? [String: Any] {
            // Nested: Body.Text.Data / Body.Html.Data
            if let textDict = bodyDict["Text"] as? [String: Any] {
                self.body = SESSentEmailBody(
                    textData: textDict["Data"] as? String,
                    htmlData: (bodyDict["Html"] as? [String: Any])?["Data"] as? String
                )
            } else {
                // Flat: Body.text_data / Body.html_data
                self.body = SESSentEmailBody(
                    textData: bodyDict["text_data"] as? String,
                    htmlData: bodyDict["html_data"] as? String
                )
            }
        } else {
            self.body = SESSentEmailBody(textData: nil, htmlData: nil)
        }

        // Parse timestamp
        if let ts = dict["Timestamp"] as? String {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            self.timestamp = iso.date(from: ts) ?? ISO8601DateFormatter().date(from: ts)
        } else {
            self.timestamp = nil
        }
    }
}
