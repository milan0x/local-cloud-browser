import Foundation

enum Route: String, CaseIterable, Identifiable {
    case s3
    case sqs
    case sns
    case ses
    case secretsManager
    case dynamodb
    case ssm
    case lambda
    case cloudwatchLogs
    case cloudWatch
    case eventBridge
    case cloudFormation
    case iam
    case apiGateway
    case acm
    case kinesis
    case kms
    case route53
    case redshift
    case opensearch
    case stepFunctions
    case ec2
    case sts

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .s3: "S3"
        case .sqs: "SQS"
        case .sns: "SNS"
        case .ses: "SES"
        case .secretsManager: "Secrets Manager"
        case .dynamodb: "DynamoDB"
        case .ssm: "Parameter Store"
        case .lambda: "Lambda"
        case .cloudwatchLogs: "CloudWatch Logs"
        case .cloudWatch: "CloudWatch"
        case .eventBridge: "EventBridge"
        case .cloudFormation: "CloudFormation"
        case .iam: "IAM"
        case .apiGateway: "API Gateway"
        case .acm: "ACM"
        case .kinesis: "Kinesis"
        case .kms: "KMS"
        case .route53: "Route 53"
        case .redshift: "Redshift"
        case .opensearch: "OpenSearch"
        case .stepFunctions: "Step Functions"
        case .ec2: "EC2"
        case .sts: "STS"
        }
    }

    var systemImage: String {
        switch self {
        case .s3: "externaldrive"
        case .sqs: "tray.2"
        case .sns: "bell"
        case .ses: "envelope"
        case .secretsManager: "key"
        case .dynamodb: "tablecells"
        case .ssm: "list.bullet.rectangle"
        case .lambda: "function"
        case .cloudwatchLogs: "doc.text.magnifyingglass"
        case .cloudWatch: "chart.xyaxis.line"
        case .eventBridge: "bolt.horizontal"
        case .cloudFormation: "square.stack.3d.down.right"
        case .iam: "person.2"
        case .apiGateway: "network"
        case .acm: "checkmark.seal"
        case .kinesis: "arrow.right.arrow.left.square"
        case .kms: "lock.shield"
        case .route53: "globe.americas"
        case .redshift: "cylinder.split.1x2"
        case .opensearch: "magnifyingglass.circle"
        case .stepFunctions: "arrow.triangle.branch"
        case .ec2: "server.rack"
        case .sts: "person.badge.key"
        }
    }
}
