import Foundation

struct CallerIdentity {
    let account: String
    let arn: String
    let userId: String

    static func getCallerIdentityCLI(endpointUrl: String, region: String) -> String {
        [
            "aws sts get-caller-identity \\",
            "  --endpoint-url '\(endpointUrl)' \\",
            "  --region '\(region)'"
        ].joined(separator: "\n")
    }
}

struct AssumedRoleCredentials {
    let accessKeyId: String
    let secretAccessKey: String
    let sessionToken: String
    let expiration: String
    let assumedRoleArn: String
    let assumedRoleId: String
}
