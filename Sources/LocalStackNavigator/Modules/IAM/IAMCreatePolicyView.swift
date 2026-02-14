import SwiftUI

struct IAMCreatePolicyView: View {
    @ObservedObject var service: IAMService
    @Environment(\.dismiss) private var dismiss
    @State private var policyName = ""
    @State private var description = ""
    @State private var policyDocument = defaultPolicyDocument
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingPolicyNames: Set<String>

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
        VStack(spacing: 0) {
            Form {
                Section("Policy") {
                    TextField("Policy name", text: $policyName)
                    TextField("Description (optional)", text: $description)
                }

                Section("Policy Document") {
                    CodeTextEditor(text: $policyDocument)
                        .frame(minHeight: 250)
                }
            }
            .formStyle(.grouped)

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

            Divider()

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
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
