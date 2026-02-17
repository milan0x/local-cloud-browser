import Foundation

@MainActor
final class FavoriteRegionStore: ObservableObject {
    @Published private(set) var regions: [String] = []

    private var profileKey: String = "default"

    init() {}

    func switchProfile(to profileId: String) {
        profileKey = profileId
        regions = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    func add(_ region: String) {
        guard !regions.contains(region) else { return }
        regions.append(region)
        save()
    }

    func remove(_ region: String) {
        regions.removeAll { $0 == region }
        save()
    }

    func isFavorite(_ region: String) -> Bool {
        regions.contains(region)
    }

    private var storageKey: String {
        "FavoriteRegions_\(profileKey)"
    }

    private func save() {
        UserDefaults.standard.set(regions, forKey: storageKey)
    }
}
