import Foundation
import SwiftUI

struct SupportCase: Identifiable, Hashable {
    let caseId: String
    let displayId: String
    let subject: String
    let status: String
    let serviceCode: String
    let categoryCode: String
    let severityCode: String
    let submittedBy: String
    let timeCreated: String
    let ccEmailAddresses: [String]
    let language: String

    var id: String { caseId }

    var timeCreatedDate: Date? {
        if let epoch = Double(timeCreated) {
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }

    var statusBadgeColor: Color {
        switch status.lowercased() {
        case "resolved": return .green
        case "unresolved": return .blue
        case "pending-customer-action": return .orange
        case "reopened": return .purple
        case "work-in-progress": return .indigo
        default: return .gray
        }
    }

    var statusDisplayName: String {
        switch status.lowercased() {
        case "resolved": return "Resolved"
        case "unresolved": return "Unresolved"
        case "pending-customer-action": return "Pending"
        case "reopened": return "Reopened"
        case "work-in-progress": return "In Progress"
        default: return status
        }
    }

    var severityBadgeColor: Color {
        switch severityCode.lowercased() {
        case "critical": return .red
        case "urgent": return .orange
        case "high": return .yellow
        case "normal": return .blue
        case "low": return .gray
        default: return .gray
        }
    }

    init(caseId: String = "", displayId: String = "", subject: String = "",
         status: String = "", serviceCode: String = "", categoryCode: String = "",
         severityCode: String = "", submittedBy: String = "", timeCreated: String = "",
         ccEmailAddresses: [String] = [], language: String = "") {
        self.caseId = caseId
        self.displayId = displayId
        self.subject = subject
        self.status = status
        self.serviceCode = serviceCode
        self.categoryCode = categoryCode
        self.severityCode = severityCode
        self.submittedBy = submittedBy
        self.timeCreated = timeCreated
        self.ccEmailAddresses = ccEmailAddresses
        self.language = language
    }

    init(from dict: [String: Any]) {
        caseId = dict["caseId"] as? String ?? ""
        displayId = dict["displayId"] as? String ?? ""
        subject = dict["subject"] as? String ?? ""
        status = dict["status"] as? String ?? ""
        serviceCode = dict["serviceCode"] as? String ?? ""
        categoryCode = dict["categoryCode"] as? String ?? ""
        severityCode = dict["severityCode"] as? String ?? ""
        submittedBy = dict["submittedBy"] as? String ?? ""
        // timeCreated can come back as a String or a Number from LocalStack
        if let str = dict["timeCreated"] as? String {
            timeCreated = str
        } else if let num = dict["timeCreated"] as? Double {
            timeCreated = String(num)
        } else {
            timeCreated = ""
        }
        ccEmailAddresses = dict["ccEmailAddresses"] as? [String] ?? []
        language = dict["language"] as? String ?? ""
    }

    // MARK: - CLI Helpers

    private static func shellEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "'", with: "'\\''")
    }

    func describeCaseCLI(endpointUrl: String, region: String) -> String {
        [
            "aws support describe-cases \\",
            "  --case-id-list '\(Self.shellEscape(caseId))' \\",
            "  --include-communications \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    func resolveCaseCLI(endpointUrl: String, region: String) -> String {
        [
            "aws support resolve-case \\",
            "  --case-id '\(Self.shellEscape(caseId))' \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }

    static func listCasesCLI(endpointUrl: String, region: String) -> String {
        [
            "aws support describe-cases \\",
            "  --endpoint-url \(endpointUrl) \\",
            "  --region \(region)",
        ].joined(separator: "\n")
    }
}

struct SupportCaseDetail {
    let supportCase: SupportCase
    let communications: [SupportCommunication]

    init(from dict: [String: Any]) {
        supportCase = SupportCase(from: dict)
        if let recentComms = dict["recentCommunications"] as? [String: Any],
           let commsList = recentComms["communications"] as? [[String: Any]] {
            communications = commsList.map { SupportCommunication(from: $0) }
        } else {
            communications = []
        }
    }
}

struct SupportCommunication: Identifiable {
    let id = UUID()
    let body: String
    let submittedBy: String
    let timeCreated: String

    var timeCreatedDate: Date? {
        if let epoch = Double(timeCreated) {
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }

    init(body: String = "", submittedBy: String = "", timeCreated: String = "") {
        self.body = body
        self.submittedBy = submittedBy
        self.timeCreated = timeCreated
    }

    init(from dict: [String: Any]) {
        body = dict["body"] as? String ?? ""
        submittedBy = dict["submittedBy"] as? String ?? ""
        if let str = dict["timeCreated"] as? String {
            timeCreated = str
        } else if let num = dict["timeCreated"] as? Double {
            timeCreated = String(num)
        } else {
            timeCreated = ""
        }
    }
}
