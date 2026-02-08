import Foundation

@MainActor
final class ConnectionProfileStore: ObservableObject {
    @Published var profiles: [ConnectionProfile] = []
    @Published var activeProfileId: UUID?

    private let profilesKey = "ConnectionProfiles"
    private let activeProfileKey = "ActiveProfileId"

    var activeProfile: ConnectionProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    init() {
        load()
        if profiles.isEmpty {
            let defaultProfile = ConnectionProfile()
            profiles = [defaultProfile]
            activeProfileId = defaultProfile.id
            save()
            Log.info("Created default connection profile", category: "Profiles")
        }
        if activeProfileId == nil {
            activeProfileId = profiles.first?.id
            save()
        }
        Log.info("Loaded \(profiles.count) profile(s), active: \(activeProfile?.name ?? "none")", category: "Profiles")
    }

    func add(_ profile: ConnectionProfile) {
        profiles.append(profile)
        save()
        Log.info("Added profile \"\(profile.name)\" (\(profile.endpoint))", category: "Profiles")
    }

    func update(_ profile: ConnectionProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            Log.warn("Update failed — profile \(profile.id) not found", category: "Profiles")
            return
        }
        profiles[index] = profile
        save()
        Log.info("Updated profile \"\(profile.name)\"", category: "Profiles")
    }

    func delete(id: UUID) {
        let name = profiles.first { $0.id == id }?.name ?? "unknown"
        profiles.removeAll { $0.id == id }
        if activeProfileId == id {
            activeProfileId = profiles.first?.id
            Log.info("Active profile deleted, switched to \(activeProfile?.name ?? "none")", category: "Profiles")
        }
        save()
        Log.info("Deleted profile \"\(name)\"", category: "Profiles")
    }

    func setActive(id: UUID) {
        activeProfileId = id
        UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
        Log.info("Switched active profile to \"\(activeProfile?.name ?? "unknown")\"", category: "Profiles")
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) {
            profiles = decoded
        } else {
            Log.warn("No saved profiles found or decode failed", category: "Profiles")
        }
        if let idString = UserDefaults.standard.string(forKey: activeProfileKey),
           let id = UUID(uuidString: idString) {
            activeProfileId = id
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        } else {
            Log.error("Failed to encode profiles for saving", category: "Profiles")
        }
        if let id = activeProfileId {
            UserDefaults.standard.set(id.uuidString, forKey: activeProfileKey)
        }
    }
}
