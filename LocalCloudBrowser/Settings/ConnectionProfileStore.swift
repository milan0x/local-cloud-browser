import Foundation

@MainActor
final class ConnectionProfileStore: ObservableObject {
    @Published var profiles: [ConnectionProfile] = []
    @Published var activeProfileId: UUID?

    private let profilesKey = "ConnectionProfiles"
    private let activeProfileKey = "ActiveProfileId"
    private let defaultProfileKey = "DefaultProfileId"

    private(set) var defaultProfileId: UUID?

    func isDefaultProfile(_ id: UUID) -> Bool {
        id == defaultProfileId
    }

    var activeProfile: ConnectionProfile? {
        profiles.first { $0.id == activeProfileId }
    }

    init() {
        load()
        if activeProfileId == nil {
            activeProfileId = profiles.first?.id
            if activeProfileId != nil { save() }
        }
        Log.info("Loaded \(profiles.count) profile(s), active: \(activeProfile?.name ?? "none")", category: "Profiles")
    }

    func add(_ profile: ConnectionProfile) {
        profiles.append(profile)
        KeychainHelper.saveCredentials(profileId: profile.id, accessKeyId: profile.accessKeyId, secretAccessKey: profile.secretAccessKey, sessionToken: profile.sessionToken)
        save()
        Log.info("Added profile \"\(profile.name)\" (\(profile.endpoint))", category: "Profiles")
    }

    func update(_ profile: ConnectionProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            Log.warn("Update failed — profile \(profile.id) not found", category: "Profiles")
            return
        }
        profiles[index] = profile
        KeychainHelper.saveCredentials(profileId: profile.id, accessKeyId: profile.accessKeyId, secretAccessKey: profile.secretAccessKey, sessionToken: profile.sessionToken)
        save()
        Log.info("Updated profile \"\(profile.name)\"", category: "Profiles")
    }

    func delete(id: UUID) {
        let name = profiles.first { $0.id == id }?.name ?? "unknown"
        profiles.removeAll { $0.id == id }
        KeychainHelper.deleteCredentials(profileId: id)
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

    private static let migratedToKeychainKey = "CredentialsMigratedToKeychain"

    private func load() {
        let hasMigrated = UserDefaults.standard.bool(forKey: Self.migratedToKeychainKey)

        if !hasMigrated {
            // First run after update: old profiles may contain plaintext credentials.
            // Decode with a permissive decoder that reads accessKeyId/secretAccessKey if present.
            if let data = UserDefaults.standard.data(forKey: profilesKey) {
                migrateLegacyProfiles(data: data)
            }
        }

        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) {
            profiles = decoded
        } else {
            Log.warn("No saved profiles found or decode failed", category: "Profiles")
        }

        // Hydrate credentials from Keychain.
        for i in profiles.indices {
            if let creds = KeychainHelper.loadCredentials(profileId: profiles[i].id) {
                profiles[i].accessKeyId = creds.accessKeyId
                profiles[i].secretAccessKey = creds.secretAccessKey
                profiles[i].sessionToken = creds.sessionToken
            }
        }

        if let idString = UserDefaults.standard.string(forKey: activeProfileKey),
           let id = UUID(uuidString: idString) {
            activeProfileId = id
        }

        if let idString = UserDefaults.standard.string(forKey: defaultProfileKey),
           let id = UUID(uuidString: idString) {
            defaultProfileId = id
        }
    }

    /// Migrate plaintext credentials from UserDefaults to Keychain (one-time).
    private func migrateLegacyProfiles(data: Data) {
        struct LegacyProfile: Codable {
            var id: UUID
            var accessKeyId: String?
            var secretAccessKey: String?
        }
        guard let legacy = (try? JSONDecoder().decode([LegacyProfile].self, from: data)) else {
            Log.warn("Failed to decode legacy profiles during migration", category: "Profiles")
            return
        }
        var migrated = 0
        for profile in legacy {
            let keyId = profile.accessKeyId ?? KeychainHelper.defaultAccessKeyId
            let secret = profile.secretAccessKey ?? KeychainHelper.defaultSecretAccessKey
            // saveCredentials skips Keychain for default "test"/"test" credentials.
            KeychainHelper.saveCredentials(profileId: profile.id, accessKeyId: keyId, secretAccessKey: secret)
            migrated += 1
        }
        // Re-save profiles without credentials (new CodingKeys will strip them).
        do {
            let decoded = try JSONDecoder().decode([ConnectionProfile].self, from: data)
            let clean = try JSONEncoder().encode(decoded)
            UserDefaults.standard.set(clean, forKey: profilesKey)
        } catch {
            Log.warn("Failed to re-encode profiles after migration: \(error.localizedDescription)", category: "Profiles")
        }
        UserDefaults.standard.set(true, forKey: Self.migratedToKeychainKey)
        Log.info("Migrated \(migrated) profile credential(s) to Keychain", category: "Profiles")
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
