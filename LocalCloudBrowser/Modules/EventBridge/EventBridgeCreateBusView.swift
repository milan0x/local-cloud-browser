import SwiftUI

struct EventBridgeCreateBusView: View {
    @ObservedObject var service: EventBridgeService
    @EnvironmentObject private var licenseManager: LicenseManager
    @Environment(\.dismiss) private var dismiss
    @State private var busName = ""
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingBusNames: Set<String>
    var onCreate: ((String) -> Void)? = nil

    private static let namePattern = try! NSRegularExpression(pattern: "^[\\.\\-_A-Za-z0-9]+$")

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Event bus name", text: $busName)
            }
            .formStyle(.grouped)

            if nameExists {
                Text("An event bus named \"\(busName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            } else if !busName.trimmingCharacters(in: .whitespaces).isEmpty && !nameMatchesPattern {
                Text("Name must contain only letters, numbers, periods, hyphens, and underscores.")
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
        busName.trimmingCharacters(in: .whitespaces)
    }

    private var nameExists: Bool {
        !trimmedName.isEmpty && existingBusNames.contains(trimmedName)
    }

    private var nameMatchesPattern: Bool {
        let range = NSRange(trimmedName.startIndex..., in: trimmedName)
        return Self.namePattern.firstMatch(in: trimmedName, range: range) != nil
    }

    private var isValid: Bool {
        !trimmedName.isEmpty && !nameExists && nameMatchesPattern && trimmedName.count <= 256
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createEventBus(name: trimmedName)
                licenseManager.incrementCreateCount(for: .eventBridge)
                onCreate?(trimmedName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
