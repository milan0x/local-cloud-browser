import Foundation

struct ACMCertificateSummary: Identifiable, Hashable {
    let certificateArn: String
    let domainName: String
    let status: String
    let type: String
    let keyAlgorithm: String
    let createdAt: Date?
    let issuedAt: Date?
    let notAfter: Date?

    var id: String { certificateArn }

    var truncatedArn: String {
        // Show just the UUID portion after the last /
        if let lastSlash = certificateArn.lastIndex(of: "/") {
            let uuid = certificateArn[certificateArn.index(after: lastSlash)...]
            if uuid.count > 8 {
                return String(uuid.prefix(8)) + "..."
            }
            return String(uuid)
        }
        return certificateArn
    }

    var displayDomain: String {
        domainName.isEmpty ? "(no domain)" : domainName
    }

    var isExpired: Bool {
        guard let notAfter else { return false }
        return notAfter < Date()
    }

    init(certificateArn: String = "", domainName: String = "", status: String = "",
         type: String = "", keyAlgorithm: String = "", createdAt: Date? = nil,
         issuedAt: Date? = nil, notAfter: Date? = nil) {
        self.certificateArn = certificateArn
        self.domainName = domainName
        self.status = status
        self.type = type
        self.keyAlgorithm = keyAlgorithm
        self.createdAt = createdAt
        self.issuedAt = issuedAt
        self.notAfter = notAfter
    }

    init(from dict: [String: Any]) {
        certificateArn = dict["CertificateArn"] as? String ?? ""
        domainName = dict["DomainName"] as? String ?? ""
        status = dict["Status"] as? String ?? ""
        type = dict["Type"] as? String ?? ""
        keyAlgorithm = dict["KeyAlgorithm"] as? String ?? ""

        if let ts = dict["CreatedAt"] as? Double {
            createdAt = Date(timeIntervalSince1970: ts)
        } else {
            createdAt = nil
        }
        if let ts = dict["IssuedAt"] as? Double {
            issuedAt = Date(timeIntervalSince1970: ts)
        } else {
            issuedAt = nil
        }
        if let ts = dict["NotAfter"] as? Double {
            notAfter = Date(timeIntervalSince1970: ts)
        } else {
            notAfter = nil
        }
    }

    func describeCertificateCLI(endpointUrl: String, region: String) -> String {
        [
            "aws acm describe-certificate \\",
            "  --certificate-arn '\(certificateArn.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    static func listCertificatesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws acm list-certificates \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }

    func deleteCertificateCLI(endpointUrl: String, region: String) -> String {
        [
            "aws acm delete-certificate \\",
            "  --certificate-arn '\(certificateArn.shellEscaped())' \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'",
        ].joined(separator: "\n")
    }
}

struct ACMCertificateDetail {
    let domainName: String
    let certificateArn: String
    let subjectAlternativeNames: [String]
    let status: String
    let type: String
    let keyAlgorithm: String
    let signatureAlgorithm: String
    let issuer: String
    let serial: String
    let notBefore: Date?
    let notAfter: Date?
    let createdAt: Date?
    let issuedAt: Date?
    let inUseBy: [String]
    let failureReason: String?

    init(from dict: [String: Any]) {
        domainName = dict["DomainName"] as? String ?? ""
        certificateArn = dict["CertificateArn"] as? String ?? ""
        subjectAlternativeNames = dict["SubjectAlternativeNames"] as? [String] ?? []
        status = dict["Status"] as? String ?? ""
        type = dict["Type"] as? String ?? ""
        keyAlgorithm = dict["KeyAlgorithm"] as? String ?? ""
        signatureAlgorithm = dict["SignatureAlgorithm"] as? String ?? ""
        issuer = dict["Issuer"] as? String ?? ""
        serial = dict["Serial"] as? String ?? ""
        inUseBy = dict["InUseBy"] as? [String] ?? []
        failureReason = dict["FailureReason"] as? String

        if let ts = dict["NotBefore"] as? Double {
            notBefore = Date(timeIntervalSince1970: ts)
        } else {
            notBefore = nil
        }
        if let ts = dict["NotAfter"] as? Double {
            notAfter = Date(timeIntervalSince1970: ts)
        } else {
            notAfter = nil
        }
        if let ts = dict["CreatedAt"] as? Double {
            createdAt = Date(timeIntervalSince1970: ts)
        } else {
            createdAt = nil
        }
        if let ts = dict["IssuedAt"] as? Double {
            issuedAt = Date(timeIntervalSince1970: ts)
        } else {
            issuedAt = nil
        }
    }
}
