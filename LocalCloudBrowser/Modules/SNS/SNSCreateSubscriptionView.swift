import SwiftUI

struct SNSCreateSubscriptionView: View {
    @ObservedObject var service: SNSService
    let topic: SNSTopic
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var selectedProtocol = "sqs"
    @State private var endpoint = ""
    @State private var isSubscribing = false
    @State private var serviceError: ServiceError?

    private let protocols = [
        ("sqs", "SQS Queue"),
        ("http", "HTTP"),
        ("https", "HTTPS"),
        ("email", "Email"),
        ("email-json", "Email (JSON)"),
        ("lambda", "Lambda"),
        ("sms", "SMS"),
    ]

    var body: some View {
        CreateFormScaffold(
            width: 420,
            isValid: isValid,
            isCreating: isSubscribing,
            createLabel: "Subscribe",
            serviceError: $serviceError,
            onCreate: subscribe
        ) {
                Picker("Protocol", selection: $selectedProtocol) {
                    ForEach(protocols, id: \.0) { proto in
                        Text(proto.1).tag(proto.0)
                    }
                }

                TextField("Endpoint", text: $endpoint, prompt: Text(placeholderForProtocol))

                Section {
                    Label(helpTextForProtocol, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var placeholderForProtocol: String {
        switch selectedProtocol {
        case "sqs": return "arn:aws:sqs:us-east-1:000000000000:my-queue"
        case "http": return "http://example.com/webhook"
        case "https": return "https://example.com/webhook"
        case "email", "email-json": return "user@example.com"
        case "lambda": return "arn:aws:lambda:us-east-1:000000000000:my-function"
        case "sms": return "+12345678901"
        default: return "Enter endpoint"
        }
    }

    private var helpTextForProtocol: String {
        switch selectedProtocol {
        case "sqs": return "Enter the ARN of an SQS queue to receive notifications."
        case "http": return "Enter an HTTP URL that will receive POST requests with notifications."
        case "https": return "Enter an HTTPS URL that will receive POST requests with notifications."
        case "email": return "Enter an email address. A confirmation email will be sent."
        case "email-json": return "Enter an email address. Notifications will be sent as JSON."
        case "lambda": return "Enter the ARN of a Lambda function to invoke."
        case "sms": return "Enter a phone number in E.164 format (e.g. +12345678901)."
        default: return "Enter the endpoint for this subscription."
        }
    }

    private var isValid: Bool {
        let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        switch selectedProtocol {
        case "http":
            return trimmed.lowercased().hasPrefix("http://")
        case "https":
            return trimmed.lowercased().hasPrefix("https://")
        case "email", "email-json":
            return trimmed.contains("@") && trimmed.contains(".")
        case "sqs", "lambda":
            return trimmed.hasPrefix("arn:")
        case "sms":
            return trimmed.hasPrefix("+") && trimmed.count >= 10
        default:
            return true
        }
    }

    private func subscribe() {
        isSubscribing = true
        serviceError = nil
        Task {
            do {
                let trimmed = endpoint.trimmingCharacters(in: .whitespaces)
                _ = try await service.subscribe(
                    topicArn: topic.topicArn,
                    protocol_: selectedProtocol,
                    endpoint: trimmed
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSubscribing = false
            }
        }
    }
}
