import SwiftUI

/// Bundles the common favorite-region wiring that every regional service list needs:
/// • Configures the region loader with the load closure and environment references
/// • Syncs the region loader when the user adds/removes a favorite
/// • Resets the region loader on full connection changes (new endpoint)
///
/// Usage: `.favoriteRegionSupport(regionLoader: regionLoader) { region in ... }`
struct FavoriteRegionSupportModifier<Item: Identifiable & Equatable>: ViewModifier {
    @ObservedObject var regionLoader: FavoriteRegionLoader<Item>
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favoriteStore: FavoriteRegionStore
    @EnvironmentObject private var profileStore: ConnectionProfileStore
    let load: (String) async throws -> [Item]

    func body(content: Content) -> some View {
        content
            .task(id: favoriteStore.regions) {
                regionLoader.configure(loader: load, appState: appState,
                                       favoriteStore: favoriteStore, profileStore: profileStore)
                regionLoader.syncFavorites(favoriteStore.regions)
            }
            .onChange(of: appState.connectionVersion) {
                regionLoader.reset()
            }
    }
}

extension View {
    func favoriteRegionSupport<Item: Identifiable & Equatable>(
        regionLoader: FavoriteRegionLoader<Item>,
        load: @escaping (String) async throws -> [Item]
    ) -> some View {
        modifier(FavoriteRegionSupportModifier(regionLoader: regionLoader, load: load))
    }
}
