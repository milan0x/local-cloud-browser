# Pagination & Efficiency Plan

## Goal
Replace "load all" patterns with paginated loading across all services. Users should see the first page fast, browse more on demand, and search across all pages when needed — without freezing the app on large datasets.

## UX Pattern (Apply Everywhere)

1. **Initial load**: Fetch first page only (service-appropriate page size)
2. **Status bar**: "Showing 200 of 200+ items" (the "+" means more pages exist)
3. **"Load More" button**: At bottom of list, loads next page and appends
4. **Local search**: Filters loaded items instantly (no API call)
5. **"Search all" prompt**: When local search has no results and more pages exist, show: _"No matches in loaded items. [Search all items]"_ (clickable)
6. **Search all behavior**: Progressively loads pages searching as it goes, stops when matches found or 10K item cap hit
7. **Cap warning**: "Showing results from first 10,000 items. Refine your search for better results."

Reference implementation: **S3ObjectBrowserView** already has page-based pagination with prev/next buttons. The new pattern is similar but uses "Load More" (append) instead of page replacement.

---

## Current Architecture

### ListLoader (Navigation/ListLoader.swift)
Generic `ListLoader<Item>` class used by nearly all list views. Takes a `fetch` closure that returns `[Item]` — currently, the fetch closure calls service methods that internally loop through ALL pages before returning.

### Service Methods
Most services have `repeat/while` loops that follow pagination tokens until exhausted:
- **JSON services** (CloudWatchLogs, SSM, SNS, etc.): use `nextToken`/`NextToken`
- **XML services** (IAM, SQS queues, SNS topics): use `Marker` + `IsTruncated`
- **REST services** (Lambda): use `NextMarker` in query string
- **DynamoDB**: Already single-page — uses `exclusiveStartKey`/`lastEvaluatedKey`, view has "Load More" button

### Key Insight
The pagination loop lives in the **service layer** (e.g., `CloudWatchLogsService.describeLogGroups()`). The `ListLoader` just calls `fetch()` and waits. To add pagination, we need to:
1. Split service methods into single-page + load-all variants
2. Create a new `PaginatedListLoader` that manages tokens and incremental loading
3. Update views to use the new loader with "Load More" UI

---

## Phase 1 — PaginatedListLoader Infrastructure

Create `Navigation/PaginatedListLoader.swift`:

```swift
@MainActor
final class PaginatedListLoader<Item: Identifiable & Equatable>: ObservableObject {
    @Published var items: [Item] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    @Published var hasMorePages = false
    @Published var totalLoaded = 0
    @Published var isSearchingAll = false

    var hasRestoredSession = false
    private var nextToken: String?
    private var lastLoadTime: Date?
    private var isFetching = false
    private let maxItems = 10_000

    // Single-page fetch: takes optional token, returns (items, nextToken?)
    typealias PageFetch = (String?) async throws -> ([Item], String?)

    func load(
        force: Bool = false,
        silent: Bool = false,
        fetch: @escaping PageFetch,
        sort: @escaping (Item, Item) -> Bool,
        afterLoad: (@MainActor (_ items: [Item]) async -> Void)? = nil
    ) {
        // Reset and load first page
        // Store fetch & sort closures for loadMore()
    }

    func loadMore() {
        // Append next page to items
    }

    func searchAll(matching predicate: (Item) -> Bool) {
        // Progressively load pages, filter, stop at maxItems or when done
    }
}
```

**Files to create:**
- `Navigation/PaginatedListLoader.swift`

**Files to modify:**
- None yet

---

## Phase 2 — Service Layer Changes (Split Methods)

Each service that currently loads all pages needs a single-page variant. The existing load-all method stays for backward compat during migration.

### Pattern for JSON services (CloudWatchLogs, SSM, etc.)

**Before:**
```swift
func describeLogGroups() async throws -> [CloudWatchLogGroup] {
    var allGroups: [CloudWatchLogGroup] = []
    var nextToken: String? = nil
    repeat {
        // ... fetch page ...
        nextToken = json["nextToken"] as? String
    } while nextToken != nil
    return allGroups
}
```

**After — add single-page method:**
```swift
func describeLogGroupsPage(nextToken: String? = nil) async throws -> ([CloudWatchLogGroup], String?) {
    var payload: [String: Any] = [:]
    if let token = nextToken { payload["nextToken"] = token }
    let data = try await client.cloudWatchLogsRequest(action: "DescribeLogGroups", payload: payload)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return ([], nil)
    }
    let groups = (json["logGroups"] as? [[String: Any]] ?? []).map { CloudWatchLogGroup(from: $0) }
    let next = json["nextToken"] as? String
    return (groups, next)
}
```

### Services to modify:

| Service | File | Method(s) | Token Type |
|---------|------|-----------|------------|
| CloudWatchLogs | `Modules/CloudWatchLogs/CloudWatchLogsService.swift` | `describeLogGroups`, `describeLogStreams`, `getLogEvents`/`filterLogEvents` | `nextToken` (JSON) |
| SSM | `Modules/SSM/SSMService.swift` | `describeParameters` | `NextToken` (JSON) |
| IAM | `Modules/IAM/IAMService.swift` | `listUsers`, `listRoles`, `listPolicies` | `Marker` (XML) |
| Lambda | `Modules/Lambda/LambdaService.swift` | `listFunctions` | `NextMarker` (REST) |
| SNS | `Modules/SNS/SNSService.swift` | `listTopics`, `listSubscriptions` | `NextToken` (XML) |
| CloudWatch | `Modules/CloudWatch/CloudWatchService.swift` | `listAlarms` | `NextToken` (JSON) |
| CloudFormation | `Modules/CloudFormation/CloudFormationService.swift` | `listStacks` | `NextToken` (JSON) |
| EventBridge | `Modules/EventBridge/EventBridgeService.swift` | list methods | `NextToken` (JSON) |
| Kinesis | `Modules/Kinesis/KinesisService.swift` | `listStreams` | `NextToken` (JSON) |
| Route53 | `Modules/Route53/Route53Service.swift` | list methods | varies |
| StepFunctions | `Modules/StepFunctions/StepFunctionsService.swift` | `listStateMachines`, `listExecutions` | `nextToken` (JSON) |
| ACM | `Modules/ACM/ACMService.swift` | `listCertificates` | `NextToken` (JSON) |
| SES | `Modules/SES/SESService.swift` | `listIdentities` | `NextToken` (JSON) |
| ResourceGroups | `Modules/ResourceGroups/ResourceGroupsService.swift` | `listGroups` | `NextToken` (JSON) |
| Support | `Modules/Support/SupportService.swift` | `describeCases` | `nextToken` (JSON) |
| Transcribe | `Modules/Transcribe/TranscribeService.swift` | `listJobs` | `NextToken` (JSON) |
| DynamoDB tables | `Modules/DynamoDB/DynamoDBService.swift` | `listTables` | `ExclusiveStartTableName` (JSON) |

**DynamoDB items** (scan/query) already return single pages — no service change needed, only view changes.

---

## Phase 3 — View Layer Changes (Group A — Critical)

### 3A. DynamoDB Item Browser
**File:** `Modules/DynamoDB/DynamoDBItemBrowserView.swift`

Already has "Load More" button and single-page loading! Needs:
- Status bar showing "Showing X of X+ items"
- "Search all" when local filter has no results but `lastEvaluatedKey != nil`
- 10K item cap on search-all
- Use `PaginatedListLoader` or keep manual (it's already close)

### 3B. CloudWatch Logs Events
**File:** `Modules/CloudWatchLogs/CloudWatchLogsEventListView.swift` (or similar)

Currently loads all log events. Needs:
- Switch to `PaginatedListLoader`
- "Load More" button
- Status bar
- Search all with cap

### 3C. S3 Search Cap
**File:** `Modules/S3/S3ObjectBrowserView.swift`

`fetchAllPages()` (line ~1671) loads everything when search is active. Needs:
- Cap at 10K objects during search
- Warning when cap hit

---

## Phase 4 — View Layer Changes (Group B — Medium Priority)

Switch these views from `ListLoader` to `PaginatedListLoader`:

| View File | Service Method |
|-----------|---------------|
| `SSMParameterListView.swift` | `describeParametersPage()` |
| `IAMEntityListView.swift` | `listUsersPage()`, `listRolesPage()`, `listPoliciesPage()` |
| `CloudWatchLogsGroupListView.swift` | `describeLogGroupsPage()` |
| `CloudWatchLogsStreamListView.swift` | `describeLogStreamsPage()` |
| `SNSSubscriptionListView.swift` | `listSubscriptionsPage()` |
| `DynamoDBTableListView.swift` | `listTablesPage()` |
| `EventBridgeRuleListView.swift` (or similar) | list rules page |
| `LambdaFunctionListView.swift` | `listFunctionsPage()` |
| `CloudFormationStackListView.swift` | `listStacksPage()` |
| `StepFunctionsStateMachineListView.swift` | `listStateMachinesPage()` |

Each view change is mechanical:
1. Replace `@StateObject private var loader = ListLoader<T>()` with `PaginatedListLoader<T>()`
2. Update `loadX()` to pass the single-page fetch closure
3. Add "Load More" button at bottom of list (when `loader.hasMorePages`)
4. Add status text: "Showing \(loader.totalLoaded)\(loader.hasMorePages ? "+" : "") items"
5. Update search to show "Search all items" when no local matches + hasMorePages

---

## Phase 5 — Safety Cap (Group C — Quick Win)

For services unlikely to hit large datasets, add a simple cap to the existing load-all methods. No UI change needed.

In each `repeat/while` loop, add before the `while`:
```swift
if allItems.count >= 10_000 { break }
```

Services: S3 buckets, SQS queues, SNS topics, Secrets Manager, KMS keys, Kinesis streams, all others not covered by Phases 3-4.

---

## Shared UI Components Needed

### "Load More" row (reusable)
A simple view to place at the bottom of any list:
```swift
struct LoadMoreRow: View {
    let isLoading: Bool
    let action: () -> Void
    // Shows "Load More" button or a spinner
}
```

### Status bar text helper
```swift
func paginationStatus(loaded: Int, hasMore: Bool) -> String {
    "Showing \(loaded)\(hasMore ? "+" : "") items"
}
```

### "Search all" prompt
When `filteredItems.isEmpty && !searchText.isEmpty && loader.hasMorePages`:
```swift
Text("No matches in loaded items.")
Button("Search all items") { loader.searchAll(matching: ...) }
```

---

## Implementation Order

1. **PaginatedListLoader** — the foundation everything else builds on
2. **LoadMoreRow + status bar** — shared UI
3. **DynamoDB items** — enhance existing pagination (already closest to done)
4. **CloudWatch Logs events** — highest impact
5. **S3 search cap** — quick safety fix
6. **SSM, IAM, CloudWatch groups/streams** — Group B, mechanical
7. **Remaining Group B services** — mechanical
8. **Safety caps on Group C** — quick loop through all load-all methods

## Testing

Unit tests should cover:
- `PaginatedListLoader`: load first page, loadMore appends, searchAll with cap, searchAll stops when matches found
- Service page methods: verify single page returned with correct next token
- Safety cap: verify loop breaks at 10K

Do NOT test SwiftUI views (per project rules).
