import Foundation

enum Route: String, CaseIterable, Identifiable {
    case s3
    case sqs
    case sns
    case secretsManager
    case dynamodb
    case ssm
    case lambda
    case cloudwatchLogs
    case eventBridge
    case cloudFormation
    case iam
    case apiGateway

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .s3: "S3"
        case .sqs: "SQS"
        case .sns: "SNS"
        case .secretsManager: "Secrets Manager"
        case .dynamodb: "DynamoDB"
        case .ssm: "Parameter Store"
        case .lambda: "Lambda"
        case .cloudwatchLogs: "CloudWatch Logs"
        case .eventBridge: "EventBridge"
        case .cloudFormation: "CloudFormation"
        case .iam: "IAM"
        case .apiGateway: "API Gateway"
        }
    }

    var systemImage: String {
        switch self {
        case .s3: "externaldrive"
        case .sqs: "tray.2"
        case .sns: "bell"
        case .secretsManager: "key"
        case .dynamodb: "tablecells"
        case .ssm: "list.bullet.rectangle"
        case .lambda: "function"
        case .cloudwatchLogs: "doc.text.magnifyingglass"
        case .eventBridge: "bolt.horizontal"
        case .cloudFormation: "square.stack.3d.down.right"
        case .iam: "person.2"
        case .apiGateway: "network"
        }
    }
}
