import SwiftUI

@MainActor
final class FavoriteRegionLoader<Item: Identifiable & Equatable>: ObservableObject {
    struct RegionState {
        var items: [Item] = []
        var isLoading = false
        var error: String?
        var isExpanded = false
    }

    @Published var states: [String: RegionState] = [:]
    @Published var pendingSelection: String?

    private(set) var loader: ((String) async throws -> [Item])?
    private weak var appState: AppState?
    private weak var favoriteStore: FavoriteRegionStore?
    private weak var profileStore: ConnectionProfileStore?

    func configure(
        loader: @escaping (String) async throws -> [Item],
        appState: AppState,
        favoriteStore: FavoriteRegionStore,
        profileStore: ConnectionProfileStore
    ) {
        self.loader = loader
        self.appState = appState
        self.favoriteStore = favoriteStore
        self.profileStore = profileStore
    }

    func toggleExpanded(_ region: String) {
        guard let loader else { return }
        if states[region] == nil {
            states[region] = RegionState()
        }
        states[region]!.isExpanded.toggle()
        if states[region]!.isExpanded {
            loadRegion(region, loader: loader)
        }
    }

    func loadAllExpanded(silent: Bool = false) {
        guard let loader else { return }
        for region in states.keys where states[region]?.isExpanded == true {
            loadRegion(region, silent: silent, loader: loader)
        }
    }

    func reset() {
        states = [:]
    }

    func syncFavorites(_ favorites: [String]) {
        for region in states.keys where !favorites.contains(region) {
            states.removeValue(forKey: region)
        }
        for region in favorites where states[region] == nil {
            states[region] = RegionState()
        }
        loadAllExpanded()
    }

    /// Switches the app to a new region while keeping the old region visible as an auto-expanded favorite.
    func switchRegion(to newRegion: String, selecting value: String) {
        guard let appState, let favoriteStore, let profileStore else { return }

        pendingSelection = value
        let oldRegion = appState.region

        if !favoriteStore.isFavorite(oldRegion) {
            favoriteStore.add(oldRegion)
        }
        if !(states[oldRegion]?.isExpanded ?? false) {
            toggleExpanded(oldRegion)
        }

        appState.region = newRegion
        if var profile = profileStore.activeProfile {
            profile.region = newRegion
            profileStore.update(profile)
        }
    }

    /// Returns and clears the pending selection if a matching item is found.
    func consumePendingSelection(from items: [Item], by keyPath: KeyPath<Item, String>) -> Item? {
        guard let pending = pendingSelection else { return nil }
        pendingSelection = nil
        return items.first(where: { $0[keyPath: keyPath] == pending })
    }

    private func loadRegion(_ region: String, silent: Bool = false, loader: @escaping (String) async throws -> [Item]) {
        guard states[region]?.isLoading != true else { return }
        if !silent {
            states[region]?.isLoading = true
            states[region]?.error = nil
        }
        Task {
            do {
                let items = try await loader(region)
                states[region]?.items = items
                states[region]?.error = nil
            } catch {
                if !silent {
                    states[region]?.error = error.localizedDescription
                }
            }
            if !silent {
                states[region]?.isLoading = false
            }
        }
    }
}
