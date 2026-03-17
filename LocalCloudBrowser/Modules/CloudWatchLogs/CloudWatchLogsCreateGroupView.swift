import SwiftUI

struct CloudWatchLogsCreateGroupView: View {
    @ObservedObject var service: CloudWatchLogsService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var logGroupName = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingGroupNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        CreateFormScaffold(
            width: 400,
            minHeight: 180,
            isValid: isValid,
            isCreating: isSaving,
            serviceError: $serviceError,
            onCreate: save
        ) {
                TextField("Log group name", text: $logGroupName)

            if nameExists {
                Text("A log group named \"\(logGroupName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
        }
    }

    private var nameExists: Bool {
        let name = logGroupName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && existingGroupNames.contains(name)
    }

    private var isValid: Bool {
        let name = logGroupName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && !nameExists
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                let name = logGroupName.trimmingCharacters(in: .whitespaces)
                try await service.createLogGroup(name: name)
                licenseManager.incrementCreateCount(for: .cloudwatchLogs)
                onCreate?(name)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
