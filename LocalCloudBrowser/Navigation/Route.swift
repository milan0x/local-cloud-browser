import Foundation

enum RouteCategory: String, CaseIterable, Identifiable {
    case compute
    case storageAndDatabase
    case messagingAndIntegration
    case networking
    case securityAndIdentity
    case managementAndGovernance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compute: "Compute"
        case .storageAndDatabase: "Storage & Database"
        case .messagingAndIntegration: "Messaging & Integration"
        case .networking: "Networking"
        case .securityAndIdentity: "Security & Identity"
        case .managementAndGovernance: "Management & Governance"
        }
    }
}

enum Route: String, CaseIterable, Identifiable {
    // Compute
    case ec2
    case lambda
    case stepFunctions

    // Storage & Database
    case s3
    case dynamodb
    case redshift
    case opensearch

    // Messaging & Integration
    case sqs
    case sns
    case ses
    case eventBridge
    case kinesis

    // Networking
    case apiGateway
    case route53

    // Security & Identity
    case iam
    case sts
    case secretsManager
    case kms
    case acm

    // Management & Governance
    case cloudFormation
    case cloudWatch
    case cloudwatchLogs
    case ssm
    case config
    case resourceGroups
    case transcribe
    case support

    var id: String { rawValue }

    var category: RouteCategory {
        switch self {
        case .ec2, .lambda, .stepFunctions:
            .compute
        case .s3, .dynamodb, .redshift, .opensearch:
            .storageAndDatabase
        case .sqs, .sns, .ses, .eventBridge, .kinesis:
            .messagingAndIntegration
        case .apiGateway, .route53:
            .networking
        case .iam, .sts, .secretsManager, .kms, .acm:
            .securityAndIdentity
        case .cloudFormation, .cloudWatch, .cloudwatchLogs, .ssm, .config, .resourceGroups, .transcribe, .support:
            .managementAndGovernance
        }
    }

    static var grouped: [(category: RouteCategory, routes: [Route])] {
        RouteCategory.allCases.map { category in
            (category: category, routes: allCases.filter { $0.category == category })
        }
    }

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
        case .config: "Config"
        case .resourceGroups: "Resource Groups"
        case .transcribe: "Transcribe"
        case .support: "Support"
        }
    }

    var isPreview: Bool {
        switch self {
        case .dynamodb: true
        default: false
        }
    }

    var supportedByMinIO: Bool {
        self == .s3
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
        case .config: "gearshape.2"
        case .resourceGroups: "square.3.layers.3d"
        case .transcribe: "waveform"
        case .support: "lifepreserver"
        }
    }
}
