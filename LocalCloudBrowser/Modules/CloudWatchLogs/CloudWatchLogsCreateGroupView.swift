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
        VStack(spacing: 0) {
            Form {
                TextField("Log group name", text: $logGroupName)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A log group named \"\(logGroupName.trimmingCharacters(in: .whitespaces))\" already exists.")
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
