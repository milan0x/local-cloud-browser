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

## Phase 6: S3 Search & Filter ✅

**Goal:** Search and filter objects in S3 buckets — local folder filter + bucket-wide search.

**Completed:**
- [x] Inline toolbar search bar: magnifying glass icon + text field + scope dropdown + clear button, rounded rect background
- [x] Scope dropdown (Menu): "Current Folder" (default) / "Entire Bucket", compact capsule label with system dropdown arrow
- [x] Current folder mode: filters visible `rowItems` by name (case-insensitive contains); `.ext` queries match file suffixes
- [x] Entire bucket mode: fetches all objects via `listAllObjects(prefix: "")`, caches in `bucketSearchResults`, filters client-side by full key path
- [x] Data pipeline: `rowItems → filteredRowItems → sortedRowItems` (current folder) or `bucketSearchResults → searchRowItems → sortedRowItems` (bucket-wide)
- [x] Status bar: "3 of 15 items" (folder filter) or "12 results" / "No results" (bucket-wide)
- [x] Empty search state: "No matches for [query]" centered placeholder
- [x] Inline loading spinner in toolbar during bucket fetch
- [x] Full-screen "Searching bucket..." spinner on first fetch
- [x] Parent `..` row suppressed during active search
- [x] Context menus and actions use `activeObjects` helper to resolve objects from either current folder or bucket search results
- [x] Auto-refresh skipped while bucket search in progress
- [x] Bucket change (`.task(id:)`) clears search state
- [x] Double-click folder during search clears search and navigates

---

## Implementation Order

Phases are independent and ordered by complexity (simplest first):
1. ~~Create Folder~~ ✅ (also includes move, back/forward, parent row, folder picker revamp)
2. Multi-Select Delete — changes Table selection type
3. Copy Object Key — trivial addition
4. Inline Text Preview — extends existing metadata sheet
5. Force Delete Bucket — new service logic + two-step confirmation flow
6. ~~S3 Search & Filter~~ ✅ (toolbar search bar with folder/bucket scope dropdown)

## Completed (outside phases)
- **Auto-refresh extraction** — reusable `AutoRefreshManager` (on `AppState`, injected as `@EnvironmentObject`), `AutoRefreshIndicatorView` (countdown in breadcrumb bar), `AutoRefreshMenuView` (single toolbar menu with Refresh Now + interval picker). Internal Task-based timer, `refreshTrigger` pattern. Both S3 bucket list and object browser auto-refresh. Settings view uses `@EnvironmentObject` directly.

## Verification

After each phase: `swift build` must pass. Manual test against running LocalStack.
