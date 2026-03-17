import SwiftUI

struct IAMCreatePolicyView: View {
    @ObservedObject var service: IAMService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var policyName = ""
    @State private var description = ""
    @State private var policyDocument = defaultPolicyDocument
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingPolicyNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    private static let namePattern = try! NSRegularExpression(pattern: "^[\\w+=,.@-]+$")

    private static let defaultPolicyDocument = """
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "s3:GetObject",
          "Resource": "arn:aws:s3:::example-bucket/*"
        }
      ]
    }
    """

    var body: some View {
        CreateFormScaffold(
            width: 520,
            minHeight: 480,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                Section("Policy") {
                    TextField("Policy name", text: $policyName)
                    TextField("Description (optional)", text: $description)
                }

                JSONInputSection(text: $policyDocument, config: .policyDocument)

            if nameExists {
                Text("A policy named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && !nameMatchesPattern {
                Text("Name must contain only alphanumeric characters and +=,.@-_")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !policyDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isValidJSON {
                Text("Policy document must be valid JSON.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private var trimmedName: String {
        policyName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingPolicyNames.contains(trimmedName)
    }

    private var nameMatchesPattern: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var isValidJSON: Bool {
        guard let data = policyDocument.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty
            && !nameExists
            && nameMatchesPattern
            && !policyDocument.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && isValidJSON
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createPolicy(
                    policyName: trimmedName,
                    policyDocument: policyDocument,
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
