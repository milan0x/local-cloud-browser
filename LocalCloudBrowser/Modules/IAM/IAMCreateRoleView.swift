import SwiftUI

struct IAMCreateRoleView: View {
    @ObservedObject var service: IAMService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var roleName = ""
    @State private var description = ""
    @State private var trustPolicy = defaultTrustPolicy
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingRoleNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    private static let namePattern = try! NSRegularExpression(pattern: "^[\\w+=,.@-]+$")

    private static let defaultTrustPolicy = """
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
    """

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Role") {
                    TextField("Role name", text: $roleName)
                    TextField("Description (optional)", text: $description)
                }

                JSONInputSection(text: $trustPolicy, config: .trustPolicy)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A role named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && !nameMatchesPattern {
                Text("Name must contain only alphanumeric characters and +=,.@-_")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trustPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidJSON {
                Text("Trust policy must be valid JSON.")
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
        .frame(width: 520)
        .frame(minHeight: 480)
        .serviceErrorAlert(error: $serviceError)
    }

    private var trimmedName: String {
        roleName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingRoleNames.contains(trimmedName)
    }

    private var nameMatchesPattern: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var isValidJSON: Bool {
        guard let data = trustPolicy.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty
            && !nameExists
            && nameMatchesPattern
            && !trustPolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isValidJSON
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createRole(
                    roleName: trimmedName,
                    assumeRolePolicyDocument: trustPolicy,
                    description: description.isEmpty ? nil : description
                )
                licenseManager.incrementCreateCount(for: .iam)
                onCreate?(trimmedName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
