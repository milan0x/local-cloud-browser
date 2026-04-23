import Foundation

/// Describes how to grant an IAM user permissions to use a given AWS service.
/// Used by the permission-denied helper sheet to produce copy-pasteable CLI commands.
struct ServicePermissionRecipe {
    let serviceKey: String            // SigV4 service name (matches CloudClient routing)
    let displayName: String           // Human-readable
    let readOnly: PolicyGrant?        // Nil when no sensible read-only grant exists
    let fullAccess: PolicyGrant?      // Full service access

    static let all: [ServicePermissionRecipe] = [
        ServicePermissionRecipe(
            serviceKey: "s3",
            displayName: "S3",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonS3FullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "iam",
            displayName: "IAM",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/IAMReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/IAMFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "sqs",
            displayName: "SQS",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonSQSFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "sns",
            displayName: "SNS",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonSNSReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonSNSFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "dynamodb",
            displayName: "DynamoDB",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "secretsmanager",
            displayName: "Secrets Manager",
            readOnly: .inline(name: "LCB-SecretsManager-ReadOnly", document: """
                {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["secretsmanager:ListSecrets","secretsmanager:DescribeSecret","secretsmanager:GetSecretValue","secretsmanager:ListSecretVersionIds"],"Resource":"*"}]}
                """),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/SecretsManagerReadWrite")
        ),
        ServicePermissionRecipe(
            serviceKey: "ssm",
            displayName: "SSM Parameter Store",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonSSMFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "monitoring",
            displayName: "CloudWatch",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/CloudWatchReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/CloudWatchFullAccessV2")
        ),
        ServicePermissionRecipe(
            serviceKey: "logs",
            displayName: "CloudWatch Logs",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/CloudWatchLogsReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "events",
            displayName: "EventBridge",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonEventBridgeReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonEventBridgeFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "scheduler",
            displayName: "EventBridge Scheduler",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonEventBridgeSchedulerReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonEventBridgeSchedulerFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "kms",
            displayName: "KMS",
            readOnly: .inline(name: "LCB-KMS-ReadOnly", document: """
                {"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["kms:ListKeys","kms:DescribeKey","kms:GetKeyPolicy","kms:ListAliases","kms:ListResourceTags"],"Resource":"*"}]}
                """),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AWSKeyManagementServicePowerUser")
        ),
        ServicePermissionRecipe(
            serviceKey: "kinesis",
            displayName: "Kinesis",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonKinesisReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonKinesisFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "firehose",
            displayName: "Kinesis Firehose",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AmazonKinesisFirehoseReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AmazonKinesisFirehoseFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "states",
            displayName: "Step Functions",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AWSStepFunctionsReadOnlyAccess"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "acm",
            displayName: "ACM",
            readOnly: .managed(arn: "arn:aws:iam::aws:policy/AWSCertificateManagerReadOnly"),
            fullAccess: .managed(arn: "arn:aws:iam::aws:policy/AWSCertificateManagerFullAccess")
        ),
        ServicePermissionRecipe(
            serviceKey: "sts",
            displayName: "STS",
            readOnly: nil,  // GetCallerIdentity is always allowed; no separate grant needed
            fullAccess: nil // AssumeRole requires trust policies on target roles
        ),
    ]

    static func forService(_ key: String) -> ServicePermissionRecipe? {
        all.first { $0.serviceKey == key }
    }
}

enum PolicyGrant {
    case managed(arn: String)
    case inline(name: String, document: String)

    func attachCommand(username: String) -> String {
        switch self {
        case .managed(let arn):
            return """
            aws iam attach-user-policy \\
              --user-name \(username) \\
              --policy-arn \(arn)
            """
        case .inline(let name, let document):
            return """
            aws iam put-user-policy \\
              --user-name \(username) \\
              --policy-name \(name) \\
              --policy-document '\(document)'
            """
        }
    }

    var shortLabel: String {
        switch self {
        case .managed(let arn):
            return arn.components(separatedBy: "/").last ?? arn
        case .inline(let name, _):
            return name
        }
    }
}
