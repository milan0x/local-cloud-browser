# S3 Improvements Plan — 6 Phases

## Phase 1: Create Folder + Folder UX ✅

**Goal:** Allow users to create "folders" (zero-byte keys ending in `/`) in the current prefix, with full file-browser navigation.

**Completed:**
- [x] Create folder: toolbar button (folder.badge.plus), sheet with validation, `S3Service.createFolder()`
- [x] Filter folder marker objects: zero-byte keys matching `currentPrefix` hidden from object list
- [x] Move objects: `S3Service.moveObject()` (GET→PUT→DELETE), context menu "Move..." with sheet (destination field, quick parent/subfolder buttons)
- [x] Back/forward navigation: history stack with toolbar chevron buttons, all nav paths go through `navigate(to:)`
- [x] Parent directory row: `..` pinned at top of list when inside subfolders, works in empty folders
- [x] Default sort: date descending (newest first)
- [x] Fix: all navigation uses `force: true` to bypass 2s debounce
- [x] Removed internal drag-and-drop (incompatible with AppKit-backed SwiftUI Table)

---

## Phase 2: Multi-Select Delete

**Goal:** Allow selecting multiple objects and deleting them in bulk.

**Files:**
- `S3ObjectBrowserView.swift` — Change `selectedRowID: RowItem.ID?` to `selectedRowIDs: Set<RowItem.ID>`, update `Table(selection:)` binding, add a "Delete Selected" button (visible when selection count > 0), add confirmation dialog for bulk delete
- `S3Service.swift` — Add `deleteObjects(bucket:keys:)` that loops and deletes each key (LocalStack Community doesn't support multi-object delete XML API reliably, so sequential single deletes is safer)

**Details:**
- Update context menu to work with multi-selection (show "Delete N items" when multiple selected)
- Confirmation dialog shows count: "Delete 5 objects?"
- Disabled in read-only mode
- Progress indication during bulk delete (optional: just reload after all complete)
- Single-select double-click/primary action still works as before

---

## Phase 3: Copy Object Key

**Goal:** Add "Copy Key" to the context menu and action buttons for objects.

**Files:**
- `S3ObjectBrowserView.swift` — Add "Copy Key" item to context menu (after "Metadata", before Divider), add a copy button to `actionsForRow`

**Details:**
- Uses `NSPasteboard.general.clearContents()` + `setString(key, forType: .string)`
- Copies the full key (e.g., `folder/subfolder/file.txt`), not just the display name
- Works for both files and folders
- No read-only restriction (read-only operation)

---

## Phase 4: Inline Text Preview

**Goal:** Show content preview for small text-based files in the metadata sheet.

**Files:**
- `S3ObjectMetadataView.swift` — Add a "Preview" section below metadata that loads and shows file content for supported types
- `S3Service.swift` — Already has `getObject()`, no changes needed

**Details:**
- Supported types: detect via content-type from HEAD response — `text/*`, `application/json`, `application/xml`, `application/yaml`, `application/javascript`
- Size limit: only preview if `detail.size <= 512_000` (500 KB)
- Show in a `ScrollView` with monospaced font, read-only `TextEditor` or `Text` with `.textSelection(.enabled)`
- Loading state: show small spinner while fetching content
- If content can't be decoded as UTF-8, show "Binary content — cannot preview"
- Increase sheet frame height to accommodate preview (e.g., from 360 to ~500, or use a flexible layout)

---

## Phase 5: Empty Bucket Before Delete (Force Delete)

**Goal:** When deleting a non-empty bucket, offer to empty it first then delete.

**Files:**
- `S3BucketListView.swift` — When `deleteBucket` fails with `BucketNotEmpty` service error, show a second confirmation: "Bucket is not empty. Delete all objects and remove bucket?" with a "Force Delete" destructive button
- `S3Service.swift` — Add `emptyBucket(bucket:)` that lists all objects (paginated) and deletes them all, then add `forceDeleteBucket(bucket:)` that calls `emptyBucket` then `deleteBucket`

**Details:**
- `emptyBucket` must handle pagination: loop `listObjects` with continuation tokens until not truncated, deleting all objects in each page
- Also delete "folder" marker objects (keys ending in `/`)
- Show progress: "Deleting objects..." spinner overlay or inline status while force-delete runs
- Disabled in read-only mode
- Use `serviceError` alert for any errors during the process

---

## Phase 6: Universal Search/Filter Bar

**Goal:** A reusable search component in the toolbar (top-right) that filters content based on the active module.

**Files:**
- **New:** `Navigation/SearchBar.swift` — A reusable `View` that renders a search text field with magnifying glass icon, clear button, and placeholder text. Takes a `Binding<String>` and a placeholder string.
- **New:** `Navigation/SearchableModule.swift` — Protocol: `protocol SearchableModule { var searchPlaceholder: String { get } }`. Each module can declare what search means for it.
- `ContentView.swift` — Add `@State searchText: String = ""` and place `SearchBar` in the toolbar. Pass `searchText` down to the active detail view. Clear `searchText` when route changes.
- `S3ObjectBrowserView.swift` — Accept `searchText: String` parameter. Filter `rowItems` (or `sortedRowItems`) by name containing the search text (case-insensitive). Show "No results for '<query>'" empty state when filter matches nothing but items exist.
- `S3BucketListView.swift` — Accept `searchText: String` parameter. Filter `buckets` list by name.

**Future-proof for other modules:**
- SQS: filter messages by body/title
- SNS: filter topics by name, subscriptions by endpoint
- Secrets Manager: filter secrets by name
- Each module view accepts `searchText` and applies its own filtering logic

**Details:**
- Search is client-side filtering of already-loaded data (not an API call)
- Debounce not needed since it's local filtering
- Search bar appears in toolbar with `magnifyingglass` icon
- Placeholder adapts: "Filter objects..." for S3 browser, "Filter buckets..." for bucket list, "Filter queues..." for SQS, etc.
- `Cmd+F` keyboard shortcut focuses the search field

---

## Implementation Order

Phases are independent and ordered by complexity (simplest first):
1. ~~Create Folder~~ ✅ (also includes move, back/forward, parent row, folder picker revamp)
2. Multi-Select Delete — changes Table selection type
3. Copy Object Key — trivial addition
4. Inline Text Preview — extends existing metadata sheet
5. Force Delete Bucket — new service logic + two-step confirmation flow
6. Universal Search — cross-cutting, touches ContentView + all modules

## Completed (outside phases)
- **Auto-refresh extraction** — reusable `AutoRefreshManager` (on `AppState`, injected as `@EnvironmentObject`), `AutoRefreshIndicatorView` (countdown in breadcrumb bar), `AutoRefreshMenuView` (single toolbar menu with Refresh Now + interval picker). Internal Task-based timer, `refreshTrigger` pattern. Both S3 bucket list and object browser auto-refresh. Settings view uses `@EnvironmentObject` directly.

## Verification

After each phase: `swift build` must pass. Manual test against running LocalStack.
