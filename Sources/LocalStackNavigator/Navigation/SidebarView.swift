import SwiftUI

    private struct EditorSheet: Identifiable {
        let id = UUID()
        let profile: ConnectionProfile?
    }

struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @State private var showProfilePicker = false
    @State private var editorSheet: EditorSheet?

    var body: some View {
        List(Route.allCases, selection: $appState.selectedRoute) { route in
            Label(route.displayName, systemImage: route.systemImage)
                .tag(route)
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

    private var connectionIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: appState.isConnected ? "link" : "link")
                .font(.caption2)
                .foregroundStyle(appState.isConnected ? .green : .gray)

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
