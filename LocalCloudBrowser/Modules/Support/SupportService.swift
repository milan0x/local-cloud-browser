import Foundation

final class SupportService: BaseService {
    // MARK: - Case Operations

    func describeCasesPage(includeResolved: Bool, token: String? = nil) async throws -> ([SupportCase], String?) {
        var payload: [String: Any] = [
            "includeResolvedCases": includeResolved,
        ]
        if let token {
            payload["nextToken"] = token
        }
        let data = try await client.supportRequest(action: "DescribeCases", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], nil)
        }
        let cases = (json["cases"] as? [[String: Any]] ?? []).map { SupportCase(from: $0) }
        return (cases, json["nextToken"] as? String)
    }

    func describeCases(includeResolved: Bool) async throws -> [SupportCase] {
        var allCases: [SupportCase] = []
        var nextToken: String?

        repeat {
            let (cases, token) = try await describeCasesPage(includeResolved: includeResolved, token: nextToken)
            allCases.append(contentsOf: cases)
            nextToken = token
            if allCases.count >= 10_000 { break }
        } while nextToken != nil

        return allCases
    }

    func describeCaseDetail(caseId: String) async throws -> SupportCaseDetail {
        let payload: [String: Any] = [
            "caseIdList": [caseId],
            "includeCommunications": true,
        ]
        let data = try await client.supportRequest(action: "DescribeCases", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cases = json["cases"] as? [[String: Any]],
              let first = cases.first else {
            throw CloudClientError.invalidURL
        }
        return SupportCaseDetail(from: first)
    }

    func createCase(
        subject: String,
        serviceCode: String,
        severityCode: String,
        categoryCode: String,
        communicationBody: String
    ) async throws -> String {
        var payload: [String: Any] = [
            "subject": subject,
            "communicationBody": communicationBody,
        ]
        if !serviceCode.isEmpty {
            payload["serviceCode"] = serviceCode
        }
        if !severityCode.isEmpty {
            payload["severityCode"] = severityCode
        }
        if !categoryCode.isEmpty {
            payload["categoryCode"] = categoryCode
        }
        let data = try await client.supportRequest(action: "CreateCase", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["caseId"] as? String else {
            throw CloudClientError.invalidURL
        }
        return id
    }

    func resolveCase(caseId: String) async throws {
        _ = try await client.supportRequest(
            action: "ResolveCase",
            payload: ["caseId": caseId]
        )
    }
}
