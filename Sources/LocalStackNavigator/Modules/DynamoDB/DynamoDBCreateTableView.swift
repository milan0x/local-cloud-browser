import SwiftUI

struct DynamoDBCreateTableView: View {
    @ObservedObject var service: DynamoDBService
    @Environment(\.dismiss) private var dismiss
    @State private var tableName = ""
    @State private var partitionKeyName = ""
    @State private var partitionKeyType = "S"
    @State private var hasSortKey = false
    @State private var sortKeyName = ""
    @State private var sortKeyType = "S"
    @State private var serviceError: ServiceError?
    @State private var isSaving = false
    var existingTableNames: Set<String>

    private static let keyTypes = [
        ("S", "String"),
        ("N", "Number"),
        ("B", "Binary"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Table") {
                    TextField("Table name", text: $tableName)
                }

                Section("Partition Key") {
                    TextField("Attribute name", text: $partitionKeyName)
                    Picker("Type", selection: $partitionKeyType) {
                        ForEach(Self.keyTypes, id: \.0) { type in
                            Text(type.1).tag(type.0)
                        }
                    }
                }

                Section("Sort Key") {
                    Toggle("Add sort key", isOn: $hasSortKey)
                    if hasSortKey {
                        TextField("Attribute name", text: $sortKeyName)
                        Picker("Type", selection: $sortKeyType) {
                            ForEach(Self.keyTypes, id: \.0) { type in
                                Text(type.1).tag(type.0)
                            }
                        }
                    }
                }

                Section("Billing") {
                    LabeledContent("Mode") {
                        Text("Pay per request")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            if nameExists {
                Text("A table named \"\(tableName.trimmingCharacters(in: .whitespaces))\" already exists.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            if hasSortKey && sortKeyNameConflict {
                Text("Sort key name must be different from partition key name.")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            Divider()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || isSaving)
            }
            .padding()
        }
        .frame(width: 420)
        .frame(minHeight: 360)
        .serviceErrorAlert(error: $serviceError)
    }

    private var nameExists: Bool {
        let name = tableName.trimmingCharacters(in: .whitespaces)
        return !name.isEmpty && existingTableNames.contains(name)
    }

    private var sortKeyNameConflict: Bool {
        let pk = partitionKeyName.trimmingCharacters(in: .whitespaces)
        let sk = sortKeyName.trimmingCharacters(in: .whitespaces)
        return !pk.isEmpty && !sk.isEmpty && pk == sk
    }

    private var isValid: Bool {
        let name = tableName.trimmingCharacters(in: .whitespaces)
        let pk = partitionKeyName.trimmingCharacters(in: .whitespaces)
        guard name.count >= 3 && name.count <= 255 else { return false }
        guard !pk.isEmpty else { return false }
        guard !nameExists else { return false }
        if hasSortKey {
            let sk = sortKeyName.trimmingCharacters(in: .whitespaces)
            guard !sk.isEmpty else { return false }
            guard !sortKeyNameConflict else { return false }
        }
        return true
    }

    private func create() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createTable(
                    tableName: tableName.trimmingCharacters(in: .whitespaces),
                    partitionKeyName: partitionKeyName.trimmingCharacters(in: .whitespaces),
                    partitionKeyType: partitionKeyType,
                    sortKeyName: hasSortKey ? sortKeyName.trimmingCharacters(in: .whitespaces) : nil,
                    sortKeyType: hasSortKey ? sortKeyType : nil
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
