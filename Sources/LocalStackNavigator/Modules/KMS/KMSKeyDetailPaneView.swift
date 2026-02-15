import SwiftUI
import AppKit

struct KMSKeyDetailPaneView: View {
    @ObservedObject var service: KMSService
    let key: KMSKey
    @ObservedObject var toolbarState: KMSToolbarState
    @EnvironmentObject private var appState: AppState

    @State private var aliases: [KMSAlias] = []
    @State private var keyPolicy: String = ""
    @State private var isLoading = false
    @State private var serviceError: ServiceError?
    @State private var showCreateAlias = false
    @State private var aliasToDelete: KMSAlias?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && aliases.isEmpty && keyPolicy.isEmpty {
                ProgressView("Loading key details...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        keyInfoSection
                        aliasesSection
                        keyPolicySection
                    }
                    .padding(16)
                }
            }
        }
        .task { loadDetails() }
        .onChange(of: key.keyId) {
            aliases = []
            keyPolicy = ""
            loadDetails()
        }
        .onChange(of: toolbarState.pendingAction) {
            guard let action = toolbarState.pendingAction else { return }
            switch action {
            case .toggleEnabled:
                toolbarState.pendingAction = nil
                toggleKeyState()
            case .viewDetails, .createKey, .scheduleDeletion:
                break
            }
        }
        .onReceive(appState.autoRefresh.triggerPublisher) {
            guard !showCreateAlias && aliasToDelete == nil && !isLoading else { return }
            loadDetails(silent: true)
        }
        .sheet(isPresented: $showCreateAlias) {
            KMSCreateAliasView(service: service, targetKeyId: key.keyId)
                .onDisappear { loadDetails(force: true) }
        }
        .alert(
            "Delete Alias",
            isPresented: Binding(
                get: { aliasToDelete != nil },
                set: { if !$0 { aliasToDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let alias = aliasToDelete {
                    deleteAlias(alias)
                }
            }
            Button("Cancel", role: .cancel) {
                aliasToDelete = nil
            }
        } message: {
            if let alias = aliasToDelete {
                Text("Are you sure you want to delete alias \"\(alias.aliasName)\"?")
            }
        }
        .serviceErrorAlert(error: $serviceError)
    }

    // MARK: - Key Info Section

    private var keyInfoSection: some View {
        GroupBox("Key Information") {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow("Key ID") {
                    CopyableValue(text: key.keyId, monospaced: true)
                }
                labeledRow("ARN") {
                    CopyableValue(text: key.arn, font: .caption, monospaced: true)
                }
                if !key.description.isEmpty {
                    labeledRow("Description") {
                        Text(key.description)
                            .textSelection(.enabled)
                    }
                }
                labeledRow("State") {
                    HStack(spacing: 6) {
                        stateBadge
                        if !appState.isReadOnly && key.keyState != "PendingDeletion" {
                            Button(key.enabled ? "Disable" : "Enable") {
                                toggleKeyState()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }
                }
                labeledRow("Usage") {
                    Text(key.keyUsage)
                        .font(.body.monospaced())
                }
                labeledRow("Spec") {
                    Text(key.keySpec)
                        .font(.body.monospaced())
                }
                labeledRow("Manager") {
                    Text(key.keyManager)
                }
                labeledRow("Origin") {
                    Text(key.origin)
                }
                if let date = key.creationDate {
                    labeledRow("Created") {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(4)
        }
    }

    private var stateBadge: some View {
        Text(key.keyState)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(stateColor.opacity(0.15), in: Capsule())
            .foregroundStyle(stateColor)
    }

    private var stateColor: Color {
        switch key.keyState {
        case "Enabled": .green
        case "Disabled": .orange
        case "PendingDeletion": .red
        default: .gray
        }
    }

    // MARK: - Aliases Section

    private var aliasesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if aliases.isEmpty {
                    Text("No aliases")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                } else {
                    ForEach(aliases) { alias in
                        HStack {
                            CopyableValue(text: alias.aliasName, monospaced: true)
                            Spacer()
                            if !appState.isReadOnly {
                                Button {
                                    aliasToDelete = alias
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .padding(4)
        } label: {
            HStack {
                Text("Aliases")
                Spacer()
                Button {
                    showCreateAlias = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .disabled(appState.isReadOnly)
            }
        }
    }

    // MARK: - Key Policy Section

    private var keyPolicySection: some View {
        GroupBox("Key Policy") {
            if keyPolicy.isEmpty {
                Text("No policy available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    Text(prettyPolicy)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(maxHeight: 300)
            }
        }
    }

    private var prettyPolicy: String {
        guard let data = keyPolicy.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8) else {
            return keyPolicy
        }
        return result
    }

    // MARK: - Helpers

    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            content()
        }
    }

    // MARK: - Data

    private func loadDetails(force: Bool = false, silent: Bool = false) {
        if !silent { isLoading = true }
        Task {
            do {
                async let aliasResult = service.listAliases(keyId: key.keyId)
                async let policyResult = service.getKeyPolicy(keyId: key.keyId)
                let (loadedAliases, loadedPolicy) = try await (aliasResult, policyResult)
                aliases = loadedAliases
                keyPolicy = loadedPolicy
            } catch {
                if !silent {
                    serviceError = error.asServiceError
                }
            }
            if !silent { isLoading = false }
        }
    }

    private func toggleKeyState() {
        Task {
            do {
                if key.enabled {
                    try await service.disableKey(keyId: key.keyId)
                } else {
                    try await service.enableKey(keyId: key.keyId)
                }
            } catch {
                serviceError = error.asServiceError
            }
        }
    }

    private func deleteAlias(_ alias: KMSAlias) {
        Task {
            do {
                try await service.deleteAlias(aliasName: alias.aliasName)
                loadDetails(force: true)
            } catch {
                serviceError = error.asServiceError
            }
        }
    }
}

/// View for creating an alias for a KMS key.
struct KMSCreateAliasView: View {
    @ObservedObject var service: KMSService
    let targetKeyId: String
    @Environment(\.dismiss) private var dismiss

    @State private var aliasName = "alias/"
    @State private var isSaving = false
    @State private var serviceError: ServiceError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Alias Name", text: $aliasName)
                    .help("Must start with \"alias/\"")
                Text("Target Key: \(targetKeyId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        .frame(width: 400)
        .serviceErrorAlert(error: $serviceError)
    }

    private var isValid: Bool {
        let name = aliasName.trimmingCharacters(in: .whitespaces)
        return name.hasPrefix("alias/") && name.count > 6
    }

    private func save() {
        isSaving = true
        serviceError = nil
        Task {
            do {
                try await service.createAlias(
                    aliasName: aliasName.trimmingCharacters(in: .whitespaces),
                    targetKeyId: targetKeyId
                )
                dismiss()
            } catch {
                serviceError = error.asServiceError
                isSaving = false
            }
        }
    }
}
