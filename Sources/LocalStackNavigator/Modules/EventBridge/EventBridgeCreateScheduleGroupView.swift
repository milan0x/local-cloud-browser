import SwiftUI

struct EventBridgeCreateScheduleGroupView: View {
    @ObservedObject var service: EventBridgeSchedulerService
    @Environment(\.dismiss) private var dismiss
    @State private var groupName = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingGroupNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    private static let namePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]+$")

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Schedule group name", text: $groupName)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A schedule group named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && !nameMatchesPattern {
                Text("Name must contain only letters, numbers, hyphens, and underscores.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && trimmedName.count > 64 {
                Text("Name must be 64 characters or fewer.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()
                .padding(.top, 8)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 400)
        .frame(minHeight: 180)
        .serviceErrorAlert(error: $serviceError)
    }

    private var trimmedName: String {
        groupName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingGroupNames.contains(trimmedName)
    }

    private var nameMatchesPattern: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !nameExists && nameMatchesPattern && trimmedName.count <= 64
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createScheduleGroup(name: trimmedName)
                onCreate?(trimmedName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
