import Foundation

final class SSMService: BaseService {
    // MARK: - Parameter Operations

    func describeParameters(region: String? = nil) async throws -> [SSMParameter] {
        var allParameters: [SSMParameter] = []
        var nextToken: String? = nil

        repeat {
            var payload: [String: Any] = [:]
            if let token = nextToken {
                payload["NextToken"] = token
            }
            let data = try await client.ssmRequest(action: "DescribeParameters", payload: payload, region: region)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                break
            }
            if let paramList = json["Parameters"] as? [[String: Any]] {
                allParameters.append(contentsOf: paramList.map { SSMParameter(from: $0) })
            }
            nextToken = json["NextToken"] as? String
        } while nextToken != nil

        return allParameters
    }

    func getParameter(name: String, withDecryption: Bool = true) async throws -> SSMParameterValue {
        let payload: [String: Any] = [
            "Name": name,
            "WithDecryption": withDecryption,
        ]
        let data = try await client.ssmRequest(action: "GetParameter", payload: payload)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CloudClientError.invalidURL
        }
        return SSMParameterValue(from: json)
    }

    func putParameter(name: String, value: String, type: String, description: String? = nil, overwrite: Bool = false) async throws {
        var payload: [String: Any] = [
            "Name": name,
            "Value": value,
            "Type": type,
            "Overwrite": overwrite,
        ]
        if let description, !description.isEmpty {
            payload["Description"] = description
        }
        _ = try await client.ssmRequest(action: "PutParameter", payload: payload)
    }

    func deleteParameter(name: String) async throws {
        _ = try await client.ssmRequest(action: "DeleteParameter", payload: ["Name": name])
    }
}
