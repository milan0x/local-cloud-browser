import SwiftUI

struct EventBridgeCreateRuleView: View {
    @ObservedObject var service: EventBridgeService
    let eventBusName: String
    var existingRuleNames: Set<String>
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var ruleName = ""
    @State private var ruleDescription = ""
    @State private var ruleType: RuleType = .eventPattern
    @State private var eventPattern = ""
    @State private var scheduleExpression = ""
    @State private var isEnabled = true
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var showJsonHelper = false

    private static let namePattern = try! NSRegularExpression(pattern: "^[\\.\\-_A-Za-z0-9]+$")

    enum RuleType: String, CaseIterable {
        case eventPattern = "Event Pattern"
        case schedule = "Schedule"
    }

    var body: some View {
        CreateFormScaffold(
            width: 520,
            isValid: isValid && !appState.isReadOnly,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Rule name", text: $ruleName)

                TextField("Description (optional)", text: $ruleDescription)

                LabeledContent("Event Bus") {
                    Text(eventBusName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Picker("Type", selection: $ruleType) {
                    ForEach(RuleType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }

                if ruleType == .eventPattern {
                    JSONInputSection(text: $eventPattern, isHelperShown: $showJsonHelper, config: .eventPattern)
                } else {
                    TextField("Schedule expression", text: $scheduleExpression, prompt: Text("rate(5 minutes) or cron(0 12 * * ? *)"))
                }

                Toggle("Enabled", isOn: $isEnabled)

            if nameExists {
                Text("A rule named \"\(trimmedName)\" already exists on this bus.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && !nameMatchesPattern {
                Text("Name must contain only letters, numbers, periods, hyphens, and underscores.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && trimmedName.count > 64 {
                Text("Name must be 64 characters or fewer.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
        .frame(minHeight: showJsonHelper ? 600 : 400)
        .animation(.easeInOut(duration: 0.2), value: showJsonHelper)
        .onChange(of: ruleType) {
            if ruleType == .schedule {
                showJsonHelper = false
            }
        }
    }

    private var trimmedName: String {
        ruleName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingRuleNames.contains(trimmedName)
    }

    private var nameMatchesPattern: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var isValid: Bool {
        guard !trimmedName.isEmpty && !nameExists && nameMatchesPattern && trimmedName.count <= 64 else {
            return false
        }
        switch ruleType {
        case .eventPattern:
            let pattern = eventPattern.trimmingCharacters(in: .whitespacesAndNewlines)
            return !pattern.isEmpty
        case .schedule:
            return !scheduleExpression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let pattern: String? = ruleType == .eventPattern
                    ? eventPattern.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
                let schedule: String? = ruleType == .schedule
                    ? scheduleExpression.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
                try await service.putRule(
                    name: trimmedName,
                    description: ruleDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                    eventBusName: eventBusName,
                    eventPattern: pattern,
                    scheduleExpression: schedule,
                    state: isEnabled ? "ENABLED" : "DISABLED"
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
