import Foundation

enum Route: String, CaseIterable, Identifiable {
    case s3
    case sqs
    case sns
    case secretsManager

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .s3: "S3"
        case .sqs: "SQS"
        case .sns: "SNS"
        case .secretsManager: "Secrets Manager"
        }
    }

    var systemImage: String {
        switch self {
        case .s3: "externaldrive"
        case .sqs: "tray.2"
        case .sns: "bell"
        case .secretsManager: "key"
        }
    }
}
