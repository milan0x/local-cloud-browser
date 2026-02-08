import SwiftUI

struct ConnectionProfilePickerView: View {
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    @EnvironmentObject private var appState: AppState

    var onRequestEdit: (ConnectionProfile?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Connections")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(profileStore.profiles) { profile in
                        profileRow(profile)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .frame(maxHeight: 240)

            Divider()

            HStack {
                Button {
                    onRequestEdit(nil)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 260)
    }

    private func profileRow(_ profile: ConnectionProfile) -> some View {
        HStack {
            Button {
                profileStore.setActive(id: profile.id)
                appState.applyProfile(profile)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: profile.id == profileStore.activeProfileId
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(profile.id == profileStore.activeProfileId ? Color.accentColor : Color.secondary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name)
                            .fontWeight(profile.id == profileStore.activeProfileId ? .semibold : .regular)
                        Text(profile.endpoint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Edit...") {
                    onRequestEdit(profile)
                }
                if profileStore.profiles.count > 1 {
                    Button("Delete", role: .destructive) {
                        profileStore.delete(id: profile.id)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(profile.id == profileStore.activeProfileId
                      ? Color.accentColor.opacity(0.1) : Color.clear)
        )
    }
}
