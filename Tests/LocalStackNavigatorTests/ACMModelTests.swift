import Testing
import Foundation
@testable import LocalStackNavigator

@Suite("ACM Models")
struct ACMModelTests {

    // MARK: - ACMCertificateSummary.truncatedArn

    @Test("truncatedArn shows first 8 chars of UUID")
    func truncatedArn() {
        let cert = ACMCertificateSummary(
            certificateArn: "arn:aws:acm:us-east-1:000:certificate/abcdefgh-1234-5678-9012-abcdefghijkl"
        )
        #expect(cert.truncatedArn == "abcdefgh...")
    }

    @Test("truncatedArn returns short UUID as-is")
    func truncatedArnShort() {
        let cert = ACMCertificateSummary(certificateArn: "arn:aws:acm:us-east-1:000:certificate/abcd1234")
        #expect(cert.truncatedArn == "abcd1234")
    }

    @Test("truncatedArn returns full ARN when no slash")
    func truncatedArnNoSlash() {
        let cert = ACMCertificateSummary(certificateArn: "no-slash-arn")
        #expect(cert.truncatedArn == "no-slash-arn")
    }

    // MARK: - displayDomain

    @Test("displayDomain returns domain name")
    func displayDomain() {
        let cert = ACMCertificateSummary(domainName: "example.com")
        #expect(cert.displayDomain == "example.com")
    }

    @Test("displayDomain shows placeholder for empty domain")
    func displayDomainEmpty() {
        let cert = ACMCertificateSummary(domainName: "")
        #expect(cert.displayDomain == "(no domain)")
    }

    // MARK: - isExpired

    @Test("isExpired true when notAfter is in the past")
    func isExpiredTrue() {
        let cert = ACMCertificateSummary(notAfter: Date(timeIntervalSince1970: 0))
        #expect(cert.isExpired == true)
    }

    @Test("isExpired false when notAfter is in the future")
    func isExpiredFalse() {
        let cert = ACMCertificateSummary(notAfter: Date(timeIntervalSinceNow: 86400))
        #expect(cert.isExpired == false)
    }

    @Test("isExpired false when notAfter is nil")
    func isExpiredNil() {
        let cert = ACMCertificateSummary()
        #expect(cert.isExpired == false)
    }

    // MARK: - init(from:)

    @Test("ACMCertificateSummary parses from dict")
    func initFromDict() {
        let cert = ACMCertificateSummary(from: [
            "CertificateArn": "arn:test",
            "DomainName": "example.com",
            "Status": "ISSUED",
            "Type": "AMAZON_ISSUED",
            "KeyAlgorithm": "RSA_2048",
            "CreatedAt": 1700000000.0,
        ])
        #expect(cert.domainName == "example.com")
        #expect(cert.status == "ISSUED")
        #expect(cert.type == "AMAZON_ISSUED")
        #expect(cert.createdAt != nil)
    }

    // MARK: - ACMCertificateDetail

    @Test("ACMCertificateDetail parses all fields")
    func detailInit() {
        let detail = ACMCertificateDetail(from: [
            "DomainName": "example.com",
            "CertificateArn": "arn:test",
            "SubjectAlternativeNames": ["example.com", "*.example.com"],
            "Status": "ISSUED",
            "Type": "AMAZON_ISSUED",
            "KeyAlgorithm": "RSA_2048",
            "SignatureAlgorithm": "SHA256WITHRSA",
            "Issuer": "Amazon",
            "Serial": "abc123",
            "InUseBy": ["arn:aws:elasticloadbalancing:test"],
        ])
        #expect(detail.subjectAlternativeNames.count == 2)
        #expect(detail.issuer == "Amazon")
        #expect(detail.inUseBy.count == 1)
    }

    // MARK: - CLI

    @Test("describeCertificateCLI generates valid command")
    func describeCertificateCLI() {
        let cert = ACMCertificateSummary(certificateArn: "arn:aws:acm:us-east-1:000:certificate/abc")
        let cli = cert.describeCertificateCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws acm describe-certificate"))
        #expect(cli.contains("arn:aws:acm:us-east-1:000:certificate/abc"))
    }

    @Test("listCertificatesCLI generates valid command")
    func listCertificatesCLI() {
        let cli = ACMCertificateSummary.listCertificatesCLI(endpointUrl: "http://localhost:4566", region: "us-east-1")
        #expect(cli.contains("aws acm list-certificates"))
    }
}
