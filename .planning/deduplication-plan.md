# Deduplication Plan (Fresh Analysis — Feb 2025)

Previous rounds (Phases 1, 2, 2.5) extracted 11 shared components and saved ~3,048 lines.
This plan targets the **remaining systematic duplication** across list views, module views, and service classes.

---

## Summary of Remaining Duplication

| Pattern | Files | Lines/file | Total waste |
|---------|-------|-----------|-------------|
| Loading/error overlay (ProgressView + retry) | 34 list views | ~15 | ~510 |
| Status bar (count + selected) | 30 list views | ~14 | ~420 |
| Empty detail placeholder ("Select a ___") | 27 module views | ~7 | ~189 |
| List header bar (title + refresh + add + delete) | 30 list views | ~25 | ~750 |
| Delete confirmation alert | 30 list views | ~20 | ~600 |
| Delete handler function | 30 list views | ~18 | ~540 |
| State variables (isLoading, errorMessage, etc.) | 34 list views | ~12 | ~408 |
| Load function (throttle + fetch + sort + restore) | 34 list views | ~37 | ~1,258 |
| Service client boilerplate | 30 services | ~5 | ~150 |
| **Total** | | | **~4,825** |

---

## Phase 1: Small Component Extractions (~900 lines saved)

**Risk: Zero.** Pure new components, mechanical find-and-replace in existing files.

### 1A: `ListLoadingContent` → `Navigation/ListLoadingContent.swift`

Replaces the if/else loading/error/content branching repeated in every list view.

**Current pattern (15 lines × 34 files):**
```swift
@ViewBuilder
private var listContent: some View {
    if isLoading && items.isEmpty {
        VStack(spacing: 12) {
            ProgressView("Loading items...")
            ConnectionRetryingLabel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let errorMessage, items.isEmpty {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundStyle(.secondary)
            Text(errorMessage)
                .foregroundStyle(.secondary)
            Button("Retry") { loadItems(force: true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
        // actual content
    }
}
```

**New component:**
```swift
struct ListLoadingContent<Content: View>: View {
    let isLoading: Bool
    let isEmpty: Bool
    let errorMessage: String?
    let loadingMessage: String
    let onRetry: () -> Void
    @ViewBuilder let content: () -> Content
}
```

**After (1 line):**
```swift
ListLoadingContent(isLoading: isLoading, isEmpty: items.isEmpty,
    errorMessage: errorMessage, loadingMessage: "Loading items...",
    onRetry: { loadItems(force: true) }
) {
    // actual content
}
```

**Files to change:** All 34 `*ListView.swift` files.

### 1B: `ListStatusBar` → `Navigation/ListStatusBar.swift`

Replaces the identical count + selection footer.

**Current pattern (14 lines × 30 files):**
```swift
if !items.isEmpty {
    Divider()
    HStack {
        Text("\(items.count) item\(items.count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundStyle(.secondary)
        if selectedIDs.count > 1 {
            Text("(\(selectedIDs.count) selected)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 4)
}
```

**New component:**
```swift
struct ListStatusBar: View {
    let totalCount: Int
    let selectedCount: Int
    let noun: String  // "key", "certificate", "queue"
}
```

**After (1 line):**
```swift
ListStatusBar(totalCount: items.count, selectedCount: selectedIDs.count, noun: "certificate")
```

**Files to change:** ~30 list view files that have this pattern.

### 1C: `EmptyDetailView` → `Navigation/EmptyDetailView.swift`

Replaces the "Select a ___" placeholder in every module view's detail pane.

**Current pattern (7 lines × 27 files):**
```swift
VStack(spacing: 8) {
    Image(systemName: "lock.shield")
        .font(.system(size: 40))
        .foregroundStyle(.secondary)
    Text("Select a key")
        .foregroundStyle(.secondary)
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

**New component:**
```swift
struct EmptyDetailView: View {
    let icon: String
    let message: String
}
```

**After (1 line):**
```swift
EmptyDetailView(icon: "lock.shield", message: "Select a key")
```

**Files to change:** All 27 `*ModuleView.swift` files + 4-8 tab-based modules with `emptyDetail()` helpers.

---

## Phase 2: List Header Bar (~570 lines saved) ✅ COMPLETE

**Risk: Low.** New parameterized component. The header is structurally identical across 30 files; only labels and actions differ.

**Completed:** Created `ListHeaderBar<Trailing: View>` with convenience init for delete button (25 files) and generic trailing ViewBuilder for custom trailing content (Support toggle). Added `subtitle` parameter for S3's "Global" label. Updated 27 files total: 19 standard list views, 2 multi-entity (EC2, IAM), 4 module views (Route53, CloudWatch, Kinesis, Config), S3, Support.

### `ListHeaderBar` → `Navigation/ListHeaderBar.swift`

**Current pattern (25 lines × 30 files):**
```swift
private var keyListHeader: some View {
    HStack {
        Text("Keys")
            .font(.headline)
            .lineLimit(1)
        AutoRefreshIndicatorView(manager: appState.autoRefresh) {
            loadKeys(force: true)
        }
        Spacer()
        ListHeaderButton("plus", isDisabled: appState.isReadOnly) {
            showCreateSheet = true
        }
        AutoRefreshMenuView(interval: Binding(...)) {
            loadKeys(force: true)
        }
        ListHeaderButton("trash", color: .red, isDisabled: deleteDisabled,
            help: "Delete Key") {
            keysToDelete = keys.filter { selectedKeyIDs.contains($0.id) }
        }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
}
```

**New component:**
```swift
struct ListHeaderBar: View {
    let title: String
    let autoRefresh: AutoRefreshManager
    let isReadOnly: Bool
    let deleteDisabled: Bool
    let deleteHelp: String
    let onRefresh: () -> Void
    let onCreate: () -> Void
    let onDelete: () -> Void
}
```

**After (~3 lines):**
```swift
ListHeaderBar(title: "Keys", autoRefresh: appState.autoRefresh,
    isReadOnly: appState.isReadOnly, deleteDisabled: keyDeleteDisabled,
    deleteHelp: deleteHelpText,
    onRefresh: { loadKeys(force: true) }, onCreate: { showCreateSheet = true },
    onDelete: { keysToDelete = keys.filter { selectedKeyIDs.contains($0.id) } })
```

**Files to change:** ~30 list view files.

**Edge cases:** A few list views have extra header buttons (ACM has "Import" + "Request" instead of single "plus"). Handle with an optional `extraButtons` ViewBuilder parameter.

---

## Phase 3: Delete Infrastructure (~970 lines saved) ✅ COMPLETE

**Completed:** Created `DeleteConfirmationModifier` with `.deleteConfirmation()` View extension (two overloads: noun-based auto-title and fully custom title/actionLabel) and `batchDelete()` free function. Updated 25 list view files: 18 standard (both alert + handler), 3 alert-only (S3, CloudWatch Alarms, SNS Subscriptions kept custom handlers), 2 with pre-filter for default items (EventBridge Bus/Schedule Groups), 2 with custom titles (KMS, Route53 Resolver with 2 alerts).

**Risk: Low-medium.** Modifier + helper. The delete alert and handler follow an identical pattern across all list views, but each calls a different service method.

### 3A: `DeleteConfirmationModifier` → `Navigation/DeleteConfirmationModifier.swift`

**Current pattern (20 lines × 30 files):**
```swift
.alert(
    itemsToDelete.count == 1 ? "Delete Item" : "Delete \(itemsToDelete.count) Items",
    isPresented: Binding(
        get: { !itemsToDelete.isEmpty },
        set: { if !$0 { itemsToDelete = [] } }
    )
) {
    Button("Delete", role: .destructive) { deleteItems(itemsToDelete) }
    Button("Cancel", role: .cancel) { itemsToDelete = [] }
} message: {
    if itemsToDelete.count == 1, let item = itemsToDelete.first {
        Text("Are you sure you want to delete \"\(item.name)\"?...")
    } else { ... }
}
```

**New modifier:**
```swift
.deleteConfirmation(
    items: $itemsToDelete,
    singularNoun: "Certificate",
    pluralNoun: "Certificates",
    nameKeyPath: \.displayDomain,
    onDelete: { deleteCertificates($0) }
)
```

### 3B: Generic delete handler pattern

**Current pattern (18 lines × 30 files):**
```swift
private func deleteItems(_ targets: [Item]) {
    Task {
        var deletedIDs: Set<Item.ID> = []
        for item in targets {
            do {
                try await service.deleteItem(id: item.id)
                deletedIDs.insert(item.id)
            } catch {
                serviceError = error.asServiceError
            }
        }
        if !deletedIDs.isEmpty {
            selectedIDs.subtract(deletedIDs)
            if let active = activeItem, deletedIDs.contains(active.id) {
                activeItem = nil
            }
            loadItems(force: true)
        }
    }
}
```

**New helper (free function or View extension):**
```swift
func performBatchDelete<Item: Identifiable>(
    _ targets: [Item],
    delete: (Item) async throws -> Void,
    selectedIDs: inout Set<Item.ID>,
    activeItem: inout Item?,
    serviceError: inout ServiceError?,
    onComplete: () -> Void
)
```

**After (~5 lines per file):**
```swift
private func deleteCertificates(_ targets: [ACMCertificateSummary]) {
    Task {
        await performBatchDelete(targets,
            delete: { try await service.deleteCertificate(arn: $0.certificateArn) },
            selectedIDs: &selectedCertIDs, activeItem: &activeCertificate,
            serviceError: &serviceError, onComplete: { loadCertificates(force: true) })
    }
}
```

**Files to change:** ~30 list view files.

**Edge cases:** Some delete functions have extra guards (EventBridge skips default bus, KMS calls "scheduleKeyDeletion"). These are handled naturally since the `delete` closure is per-service.

---

## Phase 4: List Loader (~1,200 lines saved) ✅ COMPLETE

**Completed:** Created `ListLoader<Item: Identifiable & Equatable>` ObservableObject encapsulating items, isLoading, errorMessage, hasRestoredSession, and lastLoadTime with a `load(force:silent:fetch:sort:afterLoad:)` method. Migrated 30 list view files. Excluded 4 non-standard files: EC2EntityListView (multi-entity), IAMEntityListView (multi-entity), CloudWatchLogsEventListView (pagination), DynamoDBStreamBrowserView (different pattern). Special cases: ConfigRecorderListView (async status loading in afterLoad), SNSTopicListView (subscription counts in afterLoad), Route53ResolverListView (two entity types), SNSSubscriptionListView (no session restore), CloudWatchMetricListView (no session restore, custom sort), S3BucketListView (global service, date sort).

### `ListLoader<Item>` → `Navigation/ListLoader.swift`

Encapsulates the 5 state variables and load function repeated in every list view.

**Current state declarations (12 lines × 34 files):**
```swift
@State private var items: [Item] = []
@State private var hasRestoredSession = false
@State private var isLoading = false
@State private var errorMessage: String?
@State private var lastLoadTime: Date?
```

**Current load function (37 lines × 34 files) — throttle + fetch + sort + session restore + pending selection + error handling.**

**New class:**
```swift
@MainActor
final class ListLoader<Item: Identifiable & Equatable>: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    private var lastLoadTime: Date?
    var hasRestoredSession = false

    func load(
        force: Bool = false,
        silent: Bool = false,
        fetch: () async throws -> [Item],
        sort: (Item, Item) -> Bool,
        afterLoad: (([Item]) -> Void)? = nil
    ) { ... }
}
```

**After — view declares:**
```swift
@StateObject private var loader = ListLoader<KMSKey>()
```

**After — load function becomes:**
```swift
private func loadKeys(force: Bool = false, silent: Bool = false) {
    loader.load(force: force, silent: silent,
        fetch: { [service] in try await service.listKeys() },
        sort: { $0.keyId.localizedStandardCompare($1.keyId) == .orderedAscending }
    ) { [self] items in
        if !loader.hasRestoredSession, let saved = restoreKeyId,
           let key = items.first(where: { $0.keyId == saved }) {
            selectedKeyIDs = [key.id]
            activeKey = key
        }
        loader.hasRestoredSession = true
        if let item = regionLoader.consumePendingSelection(from: items, by: \.keyId) {
            selectedKeyIDs = [item.id]
            activeKey = item
        }
    }
}
```

Reduces load function from ~37 lines to ~15 lines. Eliminates 5 @State declarations per file.

**Files to change:** All 34 `*ListView.swift` files.

**Migration pattern:** In each file:
1. Remove: `@State private var items/isLoading/errorMessage/lastLoadTime/hasRestoredSession`
2. Add: `@StateObject private var loader = ListLoader<Item>()`
3. Replace all `items` references with `loader.items`, `isLoading` with `loader.isLoading`, `errorMessage` with `loader.errorMessage`
4. Rewrite load function body to use `loader.load(...)`

---

## Phase 5: Service Base Class (~140 lines saved) ✅ COMPLETE

**Completed:** Created `LocalStackService` base class in `Networking/LocalStackService.swift` with `private(set) var client: LocalStackClient!` and `updateClient(_:)`. Migrated all 30 service classes to inherit from `LocalStackService` instead of `ObservableObject`, removing `@MainActor`, `client`, and `updateClient` from each. Special case: S3Service had a non-optional `client` with `init(client:)` — removed both, updated 2 call sites (S3ModuleView, S3BrowserWindow) to use `S3Service()`. CloudWatchLogsService had struct definitions before the class declaration — handled correctly.

### `LocalStackService` → `Networking/LocalStackService.swift`

**Current pattern (5 lines × 30 services):**
```swift
@MainActor
final class ACMService: ObservableObject {
    private var client: LocalStackClient!
    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }
    ...
}
```

**New base class:**
```swift
@MainActor
class LocalStackService: ObservableObject {
    private(set) var client: LocalStackClient!
    func updateClient(_ newClient: LocalStackClient) {
        self.client = newClient
    }
}
```

**After:**
```swift
@MainActor
final class ACMService: LocalStackService {
    // client + updateClient inherited
    ...
}
```

**Files to change:** All 30 `*Service.swift` files.

**Consideration:** Swift `ObservableObject` conformance and `@Published` properties in subclasses work fine. The base class owns the `objectWillChange` publisher. Subclass `@Published` properties trigger it automatically.

---

## Execution Notes

- **Each phase is independent** — execute in any order, though 1→2→3→4→5 is recommended
- **Each phase fits in one context window** — 30-34 mechanical file changes per phase
- **Always:** `swift build` + `swift test` after each phase
- **Phase 4 is the biggest win** (~1,200 lines) but also the most complex migration
- **Phase 3 is the second biggest** (~970 lines) with low complexity
- **Phases 1-2 are zero-risk** warmups that establish the pattern

## Estimated Total Savings

| Phase | New files | Files changed | Lines saved |
|-------|-----------|--------------|-------------|
| 1 (Components) | 3 | ~34 + 27 + 30 | ~900 |
| 2 (Header Bar) | 1 | ~30 | ~570 |
| 3 (Delete) | 1 | ~30 | ~970 |
| 4 (List Loader) | 1 | ~34 | ~1,200 |
| 5 (Service Base) | 1 | ~30 | ~140 |
| **Total** | **7** | **~91 unique files** | **~3,780** |

Combined with the ~3,048 lines saved in previous rounds, total deduplication effort: **~6,828 lines eliminated**.
