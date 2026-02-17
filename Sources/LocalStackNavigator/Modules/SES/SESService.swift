import Foundation

final class SESService: LocalStackService {
    // MARK: - Identity Operations

    func listIdentities(region: String? = nil) async throws -> [SESIdentity] {
        var identities: [SESIdentity] = []
        var nextToken: String? = nil

        repeat {
            var params: [String: String] = [:]
            if let token = nextToken {
                params["NextToken"] = token
            }
            let data = try await client.sesRequest(action: "ListIdentities", params: params, region: region)
            let xml = try SNSXMLParser.parse(data)
            let members = xml.all("member")
            for member in members {
                identities.append(SESIdentity(identity: member))
            }
            nextToken = xml.first("NextToken")
        } while nextToken != nil

        return identities
    }

    func verifyEmailIdentity(email: String) async throws {
        _ = try await client.sesRequest(action: "VerifyEmailIdentity", params: [
            "EmailAddress": email,
        ])
    }

    func verifyDomainIdentity(domain: String) async throws {
        _ = try await client.sesRequest(action: "VerifyDomainIdentity", params: [
            "Domain": domain,
        ])
    }

    func deleteIdentity(identity: String) async throws {
        _ = try await client.sesRequest(action: "DeleteIdentity", params: [
            "Identity": identity,
        ])
    }

    // MARK: - Send Email

    func sendEmail(
        source: String,
        toAddresses: [String],
        ccAddresses: [String] = [],
        subject: String,
        textBody: String?,
        htmlBody: String?
    ) async throws -> String {
        var params: [String: String] = [
            "Source": source,
            "Message.Subject.Data": subject,
        ]

        // Dot-notation for To addresses
        for (i, addr) in toAddresses.enumerated() {
            params["Destination.ToAddresses.member.\(i + 1)"] = addr
        }

        // Dot-notation for CC addresses
        for (i, addr) in ccAddresses.enumerated() {
            params["Destination.CcAddresses.member.\(i + 1)"] = addr
        }

        if let textBody, !textBody.isEmpty {
            params["Message.Body.Text.Data"] = textBody
        }
        if let htmlBody, !htmlBody.isEmpty {
            params["Message.Body.Html.Data"] = htmlBody
        }

        let data = try await client.sesRequest(action: "SendEmail", params: params)
        let xml = try SNSXMLParser.parse(data)
        return xml.first("MessageId") ?? ""
    }

    // MARK: - Sent Emails (LocalStack internal endpoint)

    func listSentEmails() async throws -> [SESSentEmail] {
        let data = try await client.get(path: "/_aws/ses")
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = json["messages"] as? [[String: Any]] else {
            return []
        }
        return messages.map { SESSentEmail(from: $0) }
    }

    func clearSentEmails() async throws {
        _ = try await client.delete(path: "/_aws/ses")
    }
}
