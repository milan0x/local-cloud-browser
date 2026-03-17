import SwiftUI

struct EventBridgeAddTargetView: View {
    @ObservedObject var service: EventBridgeService
    let ruleName: String
    let eventBusName: String
    let currentTargetCount: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var targetId = ""
    @State private var targetArn = ""
    @State private var roleArn = ""
    @State private var input = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var showJsonHelper = false

    var body: some View {
        CreateFormScaffold(
            width: 480,
            isValid: isValid && !appState.isReadOnly,
            isCreating: isSaving,
            createLabel: "Add Target",
            serviceError: $serviceError,
            onCreate: save
        ) {
                LabeledContent("Rule") {
                    Text(ruleName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                TextField("Target ID", text: $targetId)

                TextField("Target ARN", text: $targetArn, prompt: Text("arn:aws:..."))

                TextField("Role ARN (optional)", text: $roleArn)

                JSONInputSection(text: $input, isHelperShown: $showJsonHelper, config: .targetInput)

            HStack {
                Text("\(currentTargetCount)/5 targets used")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(minHeight: showJsonHelper ? 560 : 360)
        .animation(.easeInOut(duration: 0.2), value: showJsonHelper)
    }

    private var isValid: Bool {
        let id = targetId.trimmingCharacters(in: .whitespaces)
        let arn = targetArn.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty && arn.hasPrefix("arn:") && currentTargetCount < 5 else {
            return false
        }
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedInput.isEmpty {
            guard JSONInputSection.isValidJSON(trimmedInput) else {
                return false
            }
        }
        return true
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                var target: [String: Any] = [
                    "Id": targetId.trimmingCharacters(in: .whitespaces),
                    "Arn": targetArn.trimmingCharacters(in: .whitespaces),
                ]
                let trimmedRoleArn = roleArn.trimmingCharacters(in: .whitespaces)
                if !trimmedRoleArn.isEmpty {
                    target["RoleArn"] = trimmedRoleArn
                }
                let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedInput.isEmpty {
                    target["Input"] = trimmedInput
                }
                try await service.putTargets(
                    ruleName: ruleName,
                    eventBusName: eventBusName,
                    targets: [target]
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
