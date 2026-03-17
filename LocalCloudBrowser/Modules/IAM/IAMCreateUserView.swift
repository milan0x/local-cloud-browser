import SwiftUI

struct IAMCreateUserView: View {
    @ObservedObject var service: IAMService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var userName = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingUserNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    private static let namePattern = try! NSRegularExpression(pattern: "^[\\w+=,.@-]+$")

    var body: some View {
        CreateFormScaffold(
            width: 400,
            minHeight: 180,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("User name", text: $userName)

            if nameExists {
                Text("A user named \"\(trimmedName)\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !trimmedName.isEmpty && !nameMatchesPattern {
                Text("Name must contain only alphanumeric characters and +=,.@-_")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private var trimmedName: String {
        userName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingUserNames.contains(trimmedName)
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
                try await service.createUser(userName: trimmedName)
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
