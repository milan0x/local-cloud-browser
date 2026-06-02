import SwiftUI

    private struct EditorSheet: Identifiable {
        let id = UUID()
        let profile: ConnectionProfile?
        var showAdvanced: Bool = false
    }

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @EnvironmentObject private var transferManager: TransferManager
    @State private var showRegionPicker = false
    @State private var showConnectionManager = false
    @State private var showHealthWarning = false
    @State private var showConnectionError = false
    @State private var editorSheet: EditorSheet?
    @State private var showConnectionBubble = false
    @State private var bubbleDismissedByUser = false
    @AppStorage("collapsedSidebarCategories") private var collapsedCategoriesRaw = ""
    @FocusState private var isSidebarFocused: Bool

    private var hasConnection: Bool {
        !profileStore.profiles.isEmpty
    }

    var body: some View {
        List(selection: hasConnection ? $appState.selectedRoute : .constant(nil)) {
            if !hasConnection {
                addConnectionPrompt
            }
            ForEach(Route.grouped, id: \.category) { group in
                Section(isExpanded: expandedBinding(for: group.category)) {
                    ForEach(group.routes) { route in
                        let unsupported = appState.endpointType == .minio && !route.supportedByMinIO
                        if unsupported || !hasConnection {
                            HStack {
                                Label(route.displayName, systemImage: route.systemImage)
                            }
                            .opacity(0.4)
                            .allowsHitTesting(false)
                        } else {
                            HStack {
                                Label(route.displayName, systemImage: route.systemImage)
                                if route.isPreview {
                                    Text("Basic")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                            .tag(route)
                        }
                    }
                } header: {
                    Text(group.category.displayName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { toggleCategory(group.category) }
                }
            }
        }
        .listStyle(.sidebar)
        .focused($isSidebarFocused)
        .onKeyPress(.rightArrow) {
            guard !isTextFieldFirstResponder() else { return .ignored }
            guard appState.selectedRoute != nil else { return .ignored }
            appState.moduleListFocusTrigger += 1
            return .handled
        }
        .onChange(of: appState.sidebarFocusTrigger) {
            isSidebarFocused = true
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
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
        .onChange(of: appState.editActiveProfileRequest != nil) {
            if let request = appState.editActiveProfileRequest {
                appState.editActiveProfileRequest = nil
                if let profile = profileStore.activeProfile {
                    editorSheet = EditorSheet(profile: profile, showAdvanced: request.showAdvanced)
                }
            }
        }
        .sheet(item: $editorSheet) { sheet in
            ConnectionProfileEditorView(
                existing: sheet.profile,
                canDelete: sheet.profile != nil && profileStore.profiles.count > 1,
                showAdvanced: sheet.showAdvanced,
                onSave: { profile in
                    if sheet.profile != nil {
                        profileStore.update(profile)
                        if profile.id == profileStore.activeProfileId {
                            appState.applyProfile(profile)
                        }
                    } else {
                        profileStore.add(profile)
                        profileStore.setActive(id: profile.id)
                        appState.applyProfile(profile)
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

    private var addConnectionPrompt: some View {
        Button {
            editorSheet = EditorSheet(profile: nil)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                Text("Add Connection")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var nonLocalWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Non-local endpoint")
                .font(.callout)
                .fontWeight(.semibold)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: non-local endpoint")
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                connectionIndicator
                Spacer()
                regionButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var regionButton: some View {
        Button {
            showRegionPicker = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                Text(appState.region)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(transferManager.hasActiveTransfers)
        .help(transferManager.hasActiveTransfers
              ? "Region cannot be changed while transfers are in progress"
              : "Change region")
        .popover(isPresented: $showRegionPicker, arrowEdge: .bottom) {
            RegionPickerView()
        }
    }

    private var connectionLostBubble: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
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
            if hasConnection {
                if appState.connectionStatus == .connected {
                    healthStatusButton
                } else if appState.connectionError != nil {
                    connectionErrorButton
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.orange, Color.gray.opacity(0.4))
                }
            }

            Button {
                if hasConnection {
                    showConnectionManager = true
                } else {
                    editorSheet = EditorSheet(profile: nil)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(hasConnection ? appState.activeConnectionName : "No Connection")
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
            .sheet(isPresented: $showConnectionManager) {
                ConnectionManagerView()
            }
        }
    }

    private var healthStatusButton: some View {
        Button {
            showHealthWarning.toggle()
        } label: {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(Color.green)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Connected to \(appState.endpoint)")
        .accessibilityLabel("Connection status: connected")
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
        .accessibilityLabel("Connection status: error")
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
                Text("Endpoint Health")
                    .font(.headline)

                Divider()

                if info.entries.isEmpty {
                    Text("No data returned")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(info.entries) { entry in
                                HStack {
                                    Text(entry.id)
                                        .font(.body)
                                    Spacer()
                                    Text(entry.value)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 2)
                            }
                        }
                    }
                    .frame(maxHeight: 240)
                }
            } else {
                Text("Connected")
                    .font(.headline)

                Divider()

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
        }
        .padding(12)
        .frame(width: 280)
    }

    private var collapsedCategories: Set<String> {
        get { Set(collapsedCategoriesRaw.split(separator: ",").map(String.init)) }
        nonmutating set { collapsedCategoriesRaw = newValue.sorted().joined(separator: ",") }
    }

    private func expandedBinding(for category: RouteCategory) -> Binding<Bool> {
        Binding(
            get: { !collapsedCategories.contains(category.rawValue) },
            set: { isExpanded in
                var current = collapsedCategories
                if isExpanded {
                    current.remove(category.rawValue)
                } else {
                    current.insert(category.rawValue)
                }
                collapsedCategories = current
            }
        )
    }

    private func toggleCategory(_ category: RouteCategory) {
        var current = collapsedCategories
        if current.contains(category.rawValue) {
            current.remove(category.rawValue)
        } else {
            current.insert(category.rawValue)
        }
        collapsedCategories = current
    }

}
