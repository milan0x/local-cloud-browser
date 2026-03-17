import SwiftUI

struct ConnectionManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @EnvironmentObject private var appState: AppState

    @State private var selectedProfileId: UUID?
    @State private var editingProfile: ConnectionProfile?
    @State private var isAddingNew = false
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: ConnectionProfile?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Connections")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            // Profile list
            List(selection: $selectedProfileId) {
                ForEach(profileStore.profiles) { profile in
                    profileRow(profile)
                        .tag(profile.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .frame(minHeight: 120)

            Divider()

            // Footer
            HStack {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Connection") {
                    isAddingNew = true
                    editingProfile = nil
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 420, height: 340)
        .sheet(isPresented: $isAddingNew) {
            ConnectionProfileEditorView(
                onSave: { profile in
                    profileStore.add(profile)
                    profileStore.setActive(id: profile.id)
                    appState.applyProfile(profile)
                }
            )
        }
        .alert("Delete Connection?", isPresented: $showDeleteConfirmation, presenting: profileToDelete) { profile in
            Button("Cancel", role: .cancel) { profileToDelete = nil }
            Button("Delete", role: .destructive) {
                deleteProfile(profile)
                profileToDelete = nil
            }
        } message: { profile in
            Text("\(profile.name)\n\(profile.endpoint)")
        }
        .sheet(item: $editingProfile) { profile in
            ConnectionProfileEditorView(
                existing: profile,
                canDelete: profileStore.profiles.count > 1 && !profileStore.isDefaultProfile(profile.id),
                onSave: { updated in
                    profileStore.update(updated)
                    if updated.id == profileStore.activeProfileId {
                        appState.applyProfile(updated)
                    }
                },
                onDelete: {
                    profileStore.delete(id: profile.id)
                    if profileStore.activeProfileId == nil, let first = profileStore.profiles.first {
                        profileStore.setActive(id: first.id)
                        appState.applyProfile(first)
                    }
                }
            )
        }
    }

    private func profileRow(_ profile: ConnectionProfile) -> some View {
        HStack(spacing: 10) {
            // Active indicator
            Image(systemName: isActive(profile) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive(profile) ? Color.accentColor : Color.secondary.opacity(0.5))
                .font(.system(size: 14))

            // Profile info
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .fontWeight(isActive(profile) ? .semibold : .regular)
                Text(profile.endpoint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Actions
            Button {
                editingProfile = profile
            } label: {
                Image(systemName: "pencil.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .help("Edit")

            if canDelete(profile) {
                Button {
                    profileToDelete = profile
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isActive(profile) else { return }
            profileStore.setActive(id: profile.id)
            appState.applyProfile(profile)
        }
    }

    private func isActive(_ profile: ConnectionProfile) -> Bool {
        profile.id == profileStore.activeProfileId
    }

    private func canDelete(_ profile: ConnectionProfile) -> Bool {
        profileStore.profiles.count > 1 && !profileStore.isDefaultProfile(profile.id)
    }

    private func deleteProfile(_ profile: ConnectionProfile) {
        profileStore.delete(id: profile.id)
        if profileStore.activeProfileId == nil, let first = profileStore.profiles.first {
            profileStore.setActive(id: first.id)
            appState.applyProfile(first)
        }
    }
}
