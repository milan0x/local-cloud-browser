import SwiftUI

    private struct EditorSheet: Identifiable {
        let id = UUID()
        let profile: ConnectionProfile?
    }

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @State private var showProfilePicker = false
    @State private var showHealthWarning = false
    @State private var showConnectionError = false
    @State private var editorSheet: EditorSheet?
    @State private var showConnectionBubble = false
    @State private var bubbleDismissedByUser = false

    var body: some View {
        List(selection: $appState.selectedRoute) {
            ForEach(Route.grouped, id: \.category) { group in
                Section(group.category.displayName) {
                    ForEach(group.routes) { route in
                        Label(route.displayName, systemImage: route.systemImage)
                            .tag(route)
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        .navigationTitle("")
        .safeAreaInset(edge: .top) {
            if !appState.isLocalEndpoint {
                nonLocalWarning
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
                .overlay(alignment: .top) {
                    if showConnectionBubble {
                        connectionLostBubble
                            .offset(y: -36)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
        }
        .onChange(of: appState.connectionError != nil) { _, hasError in
            withAnimation(.easeInOut(duration: 0.25)) {
                if hasError {
                    if !bubbleDismissedByUser {
                        showConnectionBubble = true
                    }
                } else {
                    showConnectionBubble = false
                    bubbleDismissedByUser = false
                }
            }
        }
        .sheet(item: $editorSheet) { sheet in
            ConnectionProfileEditorView(
                existing: sheet.profile,
                canDelete: sheet.profile != nil && profileStore.profiles.count > 1 && !profileStore.isDefaultProfile(sheet.profile!.id),
                onSave: { profile in
                    if sheet.profile != nil {
                        profileStore.update(profile)
                        if profile.id == profileStore.activeProfileId {
                            appState.applyProfile(profile)
                        }
                    } else {
                        profileStore.add(profile)
                    }
                },
                onDelete: sheet.profile.map { profile in
                    {
                        profileStore.delete(id: profile.id)
                        if profileStore.activeProfileId == nil, let first = profileStore.profiles.first {
                            profileStore.setActive(id: first.id)
                            appState.applyProfile(first)
                        }
                    }
                }
            )
        }
    }

    private var nonLocalWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Non-local endpoint")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        HStack {
            connectionIndicator
            Spacer()
            readOnlyToggle
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectionLostBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
            Text("Connection lost")
                .font(.caption)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showConnectionBubble = false
                    bubbleDismissedByUser = true
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            if appState.connectionStatus == .connected {
                healthStatusButton
            } else if appState.connectionError != nil {
                connectionErrorButton
            } else {
                Image(systemName: "questionmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.orange, Color.gray.opacity(0.4))
            }

            Button {
                showProfilePicker.toggle()
            } label: {
                HStack(spacing: 4) {
                    Text(appState.activeConnectionName)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.trailing, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showProfilePicker, arrowEdge: .top) {
                ConnectionProfilePickerView { profileToEdit in
                    showProfilePicker = false
                    // Small delay so the popover dismisses before the sheet appears
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        editorSheet = EditorSheet(profile: profileToEdit)
                    }
                }
            }
        }
    }

    private var hasIssues: Bool {
        appState.healthInfo?.hasIssues ?? false
    }

    private var healthStatusButton: some View {
        Button {
            showHealthWarning.toggle()
        } label: {
            Image(systemName: hasIssues ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(hasIssues ? Color.orange : Color.green)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hasIssues ? "Some services have issues" : "Connected to \(appState.endpoint)")
        .popover(isPresented: $showHealthWarning, arrowEdge: .top) {
            healthPopover
        }
    }

    private var connectionErrorButton: some View {
        Button {
            showConnectionError.toggle()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color.orange)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Connection error — click for details")
        .popover(isPresented: $showConnectionError, arrowEdge: .top) {
            connectionErrorPopover
        }
    }

    private var connectionErrorPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection Error")
                .font(.headline)

            Divider()

            HStack {
                Text("Reason")
                    .font(.body)
                Spacer()
                Text(connectionErrorReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)

            HStack {
                Text("Endpoint")
                    .font(.body)
                Spacer()
                Text(appState.endpoint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 2)
        }
        .padding(12)
        .frame(width: 280)
    }

    private var connectionErrorReason: String {
        guard let error = appState.connectionError else { return "Unknown" }
        switch error {
        case .timeout:
            return "Timed out (5s)"
        case .httpError(let code):
            return "HTTP \(code)"
        case .networkError(let message):
            return message
        }
    }

    private var healthPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let info = appState.healthInfo {
                Text("LocalStack Health")
                    .font(.headline)

                Divider()

                healthRow("edition", info.edition)
                healthRow("version", info.version)

                Divider()

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(info.services) { service in
                            HStack {
                                Text(service.id)
                                    .font(.body)
                                Spacer()
                                Text(service.status)
                                    .font(.caption)
                                    .foregroundStyle(serviceStatusColor(for: service))
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 2)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }
        }
        .padding(12)
        .frame(width: 280)
    }

    private func healthRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.body)
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 2)
    }

    private func serviceStatusColor(for service: ServiceHealth) -> Color {
        if service.isHealthy { return .green }
        switch service.status {
        case "error", "disabled": return .red
        default: return .orange
        }
    }

    private var readOnlyToggle: some View {
        Button {
            appState.isReadOnly.toggle()
        } label: {
            Image(systemName: appState.isReadOnly ? "lock.fill" : "lock.open")
                .foregroundStyle(appState.isReadOnly ? .orange : .secondary)
        }
        .buttonStyle(.plain)
        .help(appState.isReadOnly ? "Read-only mode (click to enable writes)" : "Write mode (click to enable read-only)")
    }
}
