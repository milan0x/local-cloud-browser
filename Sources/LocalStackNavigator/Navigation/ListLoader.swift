import SwiftUI

@MainActor
final class ListLoader<Item: Identifiable & Equatable>: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    var hasRestoredSession = false
    private var lastLoadTime: Date?

    func load(
        force: Bool = false,
        silent: Bool = false,
        fetch: @escaping () async throws -> [Item],
        sort: @escaping (Item, Item) -> Bool,
        afterLoad: (@MainActor (_ items: [Item]) async -> Void)? = nil
    ) {
        guard !isLoading else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task {
            do {
                let loaded = try await fetch()
                let fresh = loaded.sorted(by: sort)
                if items != fresh {
                    items = fresh
                }
                await afterLoad?(items)
            } catch {
                if !silent {
                    errorMessage = error.localizedDescription
                }
            }
            if !silent {
                isLoading = false
                lastLoadTime = Date()
            }
        }
    }
}
