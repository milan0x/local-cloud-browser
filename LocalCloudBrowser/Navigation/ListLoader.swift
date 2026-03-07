import SwiftUI

@MainActor
final class ListLoader<Item: Identifiable & Equatable>: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    var hasRestoredSession = false
    private var lastLoadTime: Date?
    private var isFetching = false

    deinit {}

    func load(
        force: Bool = false,
        silent: Bool = false,
        fetch: @escaping () async throws -> [Item],
        sort: @escaping (Item, Item) -> Bool,
        afterLoad: (@MainActor (_ items: [Item]) async -> Void)? = nil
    ) {
        guard !isFetching else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        isFetching = true
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await fetch()
                let fresh = loaded.sorted(by: sort)
                if self.items != fresh {
                    self.items = fresh
                }
                if self.errorMessage != nil { self.errorMessage = nil }
                await afterLoad?(self.items)
            } catch {
                if !silent {
                    self.errorMessage = error.localizedDescription
                }
            }
            if !silent {
                self.isLoading = false
            }
            self.lastLoadTime = Date()
            self.isFetching = false
        }
    }
}
