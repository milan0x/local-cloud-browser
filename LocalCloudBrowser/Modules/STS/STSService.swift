import Foundation

final class STSService: BaseService {
    // MARK: - Identity

    func getCallerIdentity() async throws -> CallerIdentity {
        let data = try await client.stsRequest(action: "GetCallerIdentity")
        let xml = try SNSXMLParser.parse(data)
        return CallerIdentity(
            account: xml.first("Account") ?? "",
            arn: xml.first("Arn") ?? "",
            userId: xml.first("UserId") ?? ""
        )
    }

    // MARK: - Assume Role

    func assumeRole(roleArn: String, sessionName: String, durationSeconds: Int = 3600) async throws -> AssumedRoleCredentials {
        let params: [String: String] = [
            "RoleArn": roleArn,
            "RoleSessionName": sessionName,
            "DurationSeconds": String(durationSeconds),
        ]
        let data = try await client.stsRequest(action: "AssumeRole", params: params)
        let xml = try SNSXMLParser.parse(data)
        return AssumedRoleCredentials(
            accessKeyId: xml.first("AccessKeyId") ?? "",
            secretAccessKey: xml.first("SecretAccessKey") ?? "",
            sessionToken: xml.first("SessionToken") ?? "",
            expiration: xml.first("Expiration") ?? "",
            assumedRoleArn: xml.first("AssumedRoleId") != nil ? (xml.first("Arn") ?? "") : "",
            assumedRoleId: xml.first("AssumedRoleId") ?? ""
        )
    }
}
