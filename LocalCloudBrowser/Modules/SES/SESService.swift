import Foundation

final class SESService: BaseService {
    // MARK: - Identity Operations

    func listIdentitiesPage(region: String? = nil, token: String? = nil) async throws -> ([SESIdentity], String?) {
        var params: [String: String] = [:]
        if let token {
            params["NextToken"] = token
        }
        let data = try await client.sesRequest(action: "ListIdentities", params: params, region: region)
        let xml = try SNSXMLParser.parse(data)
        let identities = xml.all("member").map { SESIdentity(identity: $0) }
        return (identities, xml.first("NextToken"))
    }

    func listIdentities(region: String? = nil) async throws -> [SESIdentity] {
        var allIdentities: [SESIdentity] = []
        var nextToken: String? = nil

        repeat {
            let (identities, token) = try await listIdentitiesPage(region: region, token: nextToken)
            allIdentities.append(contentsOf: identities)
            nextToken = token
            if allIdentities.count >= 10_000 { break }
        } while nextToken != nil

        return allIdentities
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

    // MARK: - Sent Emails (internal endpoint)

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
