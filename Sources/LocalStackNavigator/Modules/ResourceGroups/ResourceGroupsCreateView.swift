import SwiftUI

struct ResourceGroupsCreateView: View {
    @ObservedObject var service: ResourceGroupsService
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var tagFilterRows: [TagFilterRow] = [TagFilterRow()]
    @State private var resourceTypeFilter = "AWS::AllSupported"
    @State private var isSaving = false
    @State private var serviceError: ServiceError?

    struct TagFilterRow: Identifiable {
        let id = UUID()
        var key = ""
        var values = ""
    }

    var onCreate: ((String) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Group") {
                    TextField("Name", text: $name)
                        .help("Unique name for the resource group")
                    TextField("Description", text: $description)
                        .help("Optional description")
                }

                Section("Tag Filters") {
                    ForEach($tagFilterRows) { $row in
                        HStack(spacing: 8) {
                            TextField("Key", text: $row.key)
                                .frame(minWidth: 100)
                            TextField("Values (comma-separated)", text: $row.values)
                                .frame(minWidth: 150)
                            Button {
                                tagFilterRows.removeAll { $0.id == row.id }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .disabled(tagFilterRows.count <= 1)
                        }
                    }
                    Button {
                        tagFilterRows.append(TagFilterRow())
                    } label: {
                        Label("Add Tag Filter", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                }

                Section("Resource Types") {
                    TextField("Resource Type Filter", text: $resourceTypeFilter)
                        .help("e.g., AWS::AllSupported, AWS::S3::Bucket, AWS::Lambda::Function")
                }
            }
            .formStyle(.grouped)

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
        .frame(width: 480)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let hasValidFilter = tagFilterRows.contains { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        return !trimmedName.isEmpty && hasValidFilter
    }

    private func save() {
        isSaving = true
        serviceError = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedDescription = description.trimmingCharacters(in: .whitespaces)
        let filters = tagFilterRows.compactMap { row -> TagFilter? in
            let key = row.key.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }
            let values = row.values
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return TagFilter(key: key, values: values)
        }
        let typeFilters: [String]
        let trimmedType = resourceTypeFilter.trimmingCharacters(in: .whitespaces)
        if trimmedType.isEmpty || trimmedType == "AWS::AllSupported" {
            typeFilters = []
        } else {
            typeFilters = trimmedType
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        Task {
            do {
                try await service.createGroup(
                    name: trimmedName,
                    description: trimmedDescription,
                    tagFilters: filters,
                    resourceTypeFilters: typeFilters
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
