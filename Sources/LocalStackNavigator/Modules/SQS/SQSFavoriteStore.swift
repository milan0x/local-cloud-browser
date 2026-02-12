import Foundation

@MainActor
final class SQSFavoriteStore: ObservableObject {
    @Published var favorites: [SavedSQSFavorite] = []

    private let storageKey = "SQSFavorites"

    init() {
        load()
    }

    func favorites(for queueUrl: String) -> [SavedSQSFavorite] {
        favorites
            .filter { $0.queueUrl == queueUrl }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func add(_ favorite: SavedSQSFavorite) {
        favorites.append(favorite)
        save()
    }

    func update(_ favorite: SavedSQSFavorite) {
        guard let index = favorites.firstIndex(where: { $0.id == favorite.id }) else { return }
        favorites[index] = favorite
        save()
    }

    func delete(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SavedSQSFavorite].self, from: data) else {
            return
        }
        favorites = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
