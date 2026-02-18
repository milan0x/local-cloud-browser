import SwiftUI

struct OpenSearchCreateDomainView: View {
    @ObservedObject var service: OpenSearchService
    @Environment(\.dismiss) private var dismiss
    @State private var domainName = ""
    @State private var engineVersion = "OpenSearch_2.19"
    @State private var instanceType = "t3.small.search"
    @State private var instanceCount = 1
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    @State private var hasAttemptedCreate = false

    private let engineVersions = [
        "OpenSearch_2.15", "OpenSearch_2.17", "OpenSearch_2.19", "OpenSearch_3.1",
        "Elasticsearch_7.10", "Elasticsearch_7.17",
    ]

    private let instanceTypes = [
        "t2.small.search", "t2.medium.search",
        "t3.small.search", "t3.medium.search",
        "m5.large.search",
    ]

    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Domain Name", text: $domainName)
                    .help("3-28 characters, lowercase letters, numbers, and hyphens")
                if hasAttemptedCreate && !isDomainNameValid {
                    Text(domainNameError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Picker("Engine Version", selection: $engineVersion) {
                    ForEach(engineVersions, id: \.self) { version in
                        Text(version.replacingOccurrences(of: "_", with: " ")).tag(version)
                    }
                }

                Picker("Instance Type", selection: $instanceType) {
                    ForEach(instanceTypes, id: \.self) { type in
                        Text(type).tag(type)
                    }
                }

                Stepper(value: $instanceCount, in: 1...10) {
                    HStack {
                        Text("Instance Count")
                        Spacer()
                        Text("\(instanceCount)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    hasAttemptedCreate = true
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private var trimmedName: String {
        domainName.trimmingCharacters(in: .whitespaces)
    }

    private var isDomainNameValid: Bool {
        let name = trimmedName
        guard name.count >= 3, name.count <= 28 else { return false }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private var domainNameError: String {
        let name = trimmedName
        if name.isEmpty { return "Domain name is required." }
        if name.count < 3 { return "Domain name must be at least 3 characters." }
        if name.count > 28 { return "Domain name must be at most 28 characters." }
        return "Only lowercase letters, numbers, and hyphens are allowed."
    }

    private var isValid: Bool {
        isDomainNameValid
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createDomain(
                    name: trimmedName,
                    engineVersion: engineVersion,
                    instanceType: instanceType,
                    instanceCount: instanceCount
                )
                onCreate?(trimmedName)
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
