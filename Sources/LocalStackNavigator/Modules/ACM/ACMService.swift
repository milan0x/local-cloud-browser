import Foundation

final class ACMService: LocalStackService {
    // MARK: - Certificate Operations

    func listCertificates(region: String? = nil) async throws -> [ACMCertificateSummary] {
        var allCerts: [ACMCertificateSummary] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.acmRequest(action: "ListCertificates", payload: payload, region: region)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let list = json["CertificateSummaryList"] as? [[String: Any]] {
                allCerts.append(contentsOf: list.map { ACMCertificateSummary(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allCerts
    }

    func describeCertificate(arn: String) async throws -> ACMCertificateDetail {
        let data = try await client.acmRequest(
            action: "DescribeCertificate",
            payload: ["CertificateArn": arn]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cert = json["Certificate"] as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        return ACMCertificateDetail(from: cert)
    }

    func getCertificate(arn: String) async throws -> (certificate: String, chain: String) {
        let data = try await client.acmRequest(
            action: "GetCertificate",
            payload: ["CertificateArn": arn]
        )
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LocalStackClientError.invalidURL
        }
        let cert = json["Certificate"] as? String ?? ""
        let chain = json["CertificateChain"] as? String ?? ""
        return (cert, chain)
    }

    func requestCertificate(domain: String, sans: [String], keyAlgorithm: String) async throws -> String {
        var payload: [String: Any] = [
            "DomainName": domain,
            "KeyAlgorithm": keyAlgorithm,
        ]
        if !sans.isEmpty {
            payload["SubjectAlternativeNames"] = sans
        }
        let data = try await client.acmRequest(action: "RequestCertificate", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arn = json["CertificateArn"] as? String else {
            throw LocalStackClientError.invalidURL
        }
        return arn
    }

    func importCertificate(cert: String, key: String, chain: String?) async throws -> String {
        var payload: [String: Any] = [
            "Certificate": Data(cert.utf8).base64EncodedString(),
            "PrivateKey": Data(key.utf8).base64EncodedString(),
        ]
        if let chain, !chain.isEmpty {
            payload["CertificateChain"] = Data(chain.utf8).base64EncodedString()
        }
        let data = try await client.acmRequest(action: "ImportCertificate", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arn = json["CertificateArn"] as? String else {
            throw LocalStackClientError.invalidURL
        }
        return arn
    }

    func deleteCertificate(arn: String) async throws {
        _ = try await client.acmRequest(
            action: "DeleteCertificate",
            payload: ["CertificateArn": arn]
        )
    }
}
