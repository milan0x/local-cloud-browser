import Foundation

@MainActor
final class SupportService: ObservableObject {
    private var client: LocalStackClient!

    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }

    // MARK: - Case Operations

    func describeCases(includeResolved: Bool) async throws -> [SupportCase] {
        var allCases: [SupportCase] = []
        var nextToken: String?

        repeat {
            var payload: [String: Any] = [
                "includeResolvedCases": includeResolved,
            ]
            if let token = nextToken {
                payload["nextToken"] = token
            }
            let data = try await client.supportRequest(action: "DescribeCases", payload: payload)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let list = json["cases"] as? [[String: Any]] {
                allCases.append(contentsOf: list.map { SupportCase(from: $0) })
            }
            nextToken = json["nextToken"] as? String
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
            throw LocalStackClientError.invalidURL
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
            throw LocalStackClientError.invalidURL
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
