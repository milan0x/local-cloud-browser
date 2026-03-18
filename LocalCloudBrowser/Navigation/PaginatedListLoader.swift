import SwiftUI

@MainActor
final class PaginatedListLoader<Item: Identifiable & Equatable>: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var hasMorePages = false
    @Published var isSearchingAll = false
    @Published var searchAllHitCap = false

    var hasRestoredSession = false
    private var nextToken: String?
    private var lastLoadTime: Date?
    private var isFetching = false
    private var storedFetch: PageFetch?
    private var storedSort: ((Item, Item) -> Bool)?
    private let maxItems = 10_000

    typealias PageFetch = (String?) async throws -> ([Item], String?)

    deinit {}

    var totalLoaded: Int { items.count }

    func load(
        force: Bool = false,
        silent: Bool = false,
        fetch: @escaping PageFetch,
        sort: @escaping (Item, Item) -> Bool,
        afterLoad: (@MainActor (_ items: [Item]) async -> Void)? = nil
    ) {
        guard !isFetching else { return }
        if !force, let lastLoadTime, Date().timeIntervalSince(lastLoadTime) < 2.0 {
            return
        }
        storedFetch = fetch
        storedSort = sort
        isFetching = true
        if !silent {
            isLoading = true
            errorMessage = nil
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let (loaded, token) = try await fetch(nil)
                let fresh = loaded.sorted(by: sort)
                if self.items != fresh {
                    self.items = fresh
                }
                self.nextToken = token
                self.hasMorePages = token != nil
                self.searchAllHitCap = false
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

    func loadMore() {
        guard !isFetching, hasMorePages, let fetch = storedFetch, let sort = storedSort else { return }
        isFetching = true
        isLoadingMore = true
        Task { [weak self] in
            guard let self else { return }
            do {
                let (loaded, token) = try await fetch(self.nextToken)
                var combined = self.items + loaded
                combined.sort(by: sort)
                if self.items != combined {
                    self.items = combined
                }
                self.nextToken = token
                self.hasMorePages = token != nil
                if self.errorMessage != nil { self.errorMessage = nil }
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoadingMore = false
            self.lastLoadTime = Date()
            self.isFetching = false
        }
    }

    func searchAll(matching predicate: @escaping @Sendable (Item) -> Bool) {
        guard !isFetching, hasMorePages, let fetch = storedFetch, let sort = storedSort else { return }
        isFetching = true
        isSearchingAll = true
        searchAllHitCap = false
        Task { [weak self] in
            guard let self else { return }
            var allItems = self.items
            var token = self.nextToken
            do {
                while let currentToken = token, allItems.count < self.maxItems {
                    let (loaded, nextToken) = try await fetch(currentToken)
                    allItems.append(contentsOf: loaded)
                    token = nextToken
                    if token == nil { break }
                    let hasMatches = loaded.contains(where: predicate)
                    if hasMatches && allItems.count > self.items.count + 500 {
                        break
                    }
                }
                allItems.sort(by: sort)
                if self.items != allItems {
                    self.items = allItems
                }
                self.nextToken = token
                self.hasMorePages = token != nil
                self.searchAllHitCap = allItems.count >= self.maxItems && token != nil
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isSearchingAll = false
            self.lastLoadTime = Date()
            self.isFetching = false
        }
    }
}
