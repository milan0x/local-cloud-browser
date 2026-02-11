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

## Phase 2: Multi-Select Delete ✅

**Goal:** Allow selecting multiple objects and deleting them in bulk.

**Completed:**
- [x] Table selection changed to `Set<RowItem.ID>` for multi-selection (objects) and `Set<S3Bucket.ID>` (buckets)
- [x] `S3Service.deleteObjects(bucket:keys:)` — sequential single deletes (LocalStack Community compat)
- [x] Context menus adapt: "Delete N Items" / "Delete N Buckets" for multi-select
- [x] Native `.alert()` confirmation lists all selected item names on separate lines
- [x] Selection state cleared after successful deletion
- [x] Disabled in read-only mode
- [x] Single-select double-click/primary action still works
- [x] Multi-select move: "Move N Items..." context menu action

---

## Phase 3: Copy Key / S3 URI ✅

**Goal:** Add clipboard copy options to context menus for objects, folders, and buckets.

**Completed:**
- [x] Single file: "Copy Key" + "Copy S3 URI" + "Copy as AWS JSON" in right-click context menu
- [x] Single folder: "Copy Key" + "Copy S3 URI" + "Copy as AWS JSON" in right-click context menu
- [x] Multi-select objects: "Copy N Paths" (newline-separated) + "Copy N S3 URIs" (newline-separated) + "Copy as AWS JSON" (`{"Objects":[{"Key":...}]}`)
- [x] Single bucket: "Copy Name" + "Copy S3 URI" (`s3://bucket`) in right-click context menu
- [x] Multi-select buckets: "Copy N Names" (newline-separated) + "Copy N S3 URIs" (newline-separated)
- [x] AWS JSON format directly usable with `aws s3api delete-objects --delete`
- [x] No read-only restriction (read-only operation)
- [x] Uses `NSPasteboard.general` for clipboard

---

## Phase 4: Quick Look Preview ✅

**Goal:** Preview S3 objects using macOS native Quick Look — supports text, images, PDFs, videos, audio, and more.

**Completed:**
- [x] **Spacebar** trigger — `.onKeyPress(.space)` on selected single file (macOS 14+)
- [x] **Right-click → "Quick Look"** — context menu item for single files (after Download)
- [x] **Eye button** — `eye` SF Symbol in row actions area (between Download and Metadata), files only
- [x] **Size limit setting** — `Stepper` in Settings (1–50 MB, default 10 MB), stored as `previewSizeLimitMB` on `AppState` with `UserDefaults` persistence
- [x] **Over-limit alert** (under 300 MB): "Preview Anyway" / "Open Settings" / "Cancel"
- [x] **Hard cap alert** (over 300 MB): "File too large — use Download" with only "OK"
- [x] **Streaming download** — `URLSession.shared.download(from:)` writes directly to disk (near-zero memory)
- [x] **Temp file management** — `{NSTemporaryDirectory()}/localstack-navigator-preview/` subfolder, cleaned on app launch (`AppPreferences.cleanPreviewTempDirectory()` in app init)
- [x] **Preview title** — `"filename.ext — Temporary Preview"` via `QLPreviewItem.previewItemTitle`
- [x] **Download overlay** — `.ultraThinMaterial` background with spinner + "Downloading for preview..."
- [x] **Download error alert** — shows error message if download fails
- [x] **`S3QuickLookManager`** — `ObservableObject` managing download, `QLPreviewPanel` presentation, temp cleanup
- [x] **`QuickLookPanelController`** — `@preconcurrency QLPreviewPanelDataSource` + `QLPreviewPanelDelegate` for Swift 6 concurrency compat
- [x] Works in main window and new browser windows (client injected via `@EnvironmentObject`)

**Skipped:**
- Custom syntax highlighting (Quick Look handles it natively)
- Live/real-time refresh of preview content (close and re-preview to see updates)
- Inline preview in metadata sheet (Quick Look is better)
- Preview for folders
- Multi-select preview

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

**Goal:** Search and filter objects in the current folder.

**Completed:**
- [x] Reusable `SearchBarView` component: extracted to `Navigation/SearchBarView.swift`, generic `TrailingContent` parameter, fixed 200pt width (no layout shift), clear button always present (opacity toggle)
- [x] Inline toolbar search bar: magnifying glass icon + text field + clear button, rounded rect background, placeholder "Search in folder"
- [x] Current folder filter: filters visible `rowItems` by name (case-insensitive contains); `.ext` queries match file suffixes
- [x] Data pipeline: `rowItems → filteredRowItems → sortedRowItems`
- [x] Status bar: "3 of 15 items" (when filtering)
- [x] Empty search state: "No matches for [query]" centered placeholder
- [x] Parent `..` row suppressed during active search
- [x] Bucket change (`.task(id:)`) clears search state
- [x] Double-click folder during search clears search and navigates

**Removed (simplification):**
- Bucket-wide search scope ("Entire Bucket") — removed to reduce complexity. Scope dropdown, `bucketSearchResults`, `searchRowItems`, `activeObjects`, `SearchScope` enum, `performBucketSearch()` all removed. Current-folder filtering covers the primary use case.

---

## Implementation Order

Phases are independent and ordered by complexity (simplest first):
1. ~~Create Folder~~ ✅ (also includes move, back/forward, parent row, folder picker revamp)
2. ~~Multi-Select Delete~~ ✅ (Set-based selection, bulk delete, adapted context menus)
3. ~~Copy Key / S3 URI~~ ✅ (Copy Key, Copy S3 URI, JSON array for multi-select, buckets + objects)
4. ~~Quick Look Preview~~ ✅ (QLPreviewPanel, streaming download, size limit settings, eye button, spacebar)
5. Force Delete Bucket — new service logic + two-step confirmation flow
6. ~~S3 Search & Filter~~ ✅ (reusable SearchBarView, current-folder filter only)

## Completed (outside phases)
- **Auto-refresh extraction** — reusable `AutoRefreshManager` (on `AppState`, injected as `@EnvironmentObject`), `AutoRefreshIndicatorView` (countdown in breadcrumb bar), `AutoRefreshMenuView` (single toolbar menu with Refresh Now + interval picker, `.menuStyle(.borderlessButton)` + `.fixedSize()` for compact icon). Internal Task-based timer, `refreshTrigger` pattern. Both S3 bucket list and object browser auto-refresh. Settings view uses `@EnvironmentObject` directly.
- **Bucket list header layout** — Rearranged: Buckets label → countdown → spacer → + (create, accent-colored) → refresh menu → trash (always visible, disabled until selection). Pane width increased from 220pt to 260pt to prevent layout cramping when delete button appears.
- **Native delete dialogs** — All delete confirmations (objects, folders, buckets) use `.alert()` (native macOS NSAlert) instead of `.confirmationDialog()` or custom sheets. Multi-delete lists each item name on separate lines. Removed the large custom `folderDeleteSheet` view.
- **Right-click context menus on empty areas** — Object browser empty state: right-click shows "Create Folder" + "Upload File". Bucket list empty state: right-click shows "Create Bucket". Uses `.contentShape(Rectangle())` for full-area hit detection. Also added "Create Bucket" to per-row bucket context menu.
- **SearchBarView component** — Reusable `Navigation/SearchBarView.swift` with generic `TrailingContent`, fixed 200pt width, convenience init for no trailing content (`EmptyView`). Used by S3 object browser; ready for future SQS/SNS/Secrets Manager modules.
- **S3 global region indicator** — Region badge in toolbar shows "Global" (dimmed, 50% opacity) when viewing S3 instead of the region name. Tooltip on hover: "S3 buckets are global on LocalStack, not region-specific". Bucket list header also shows small "Global" caption in `.caption2` + `.tertiary`. Other modules still show the actual region.
- **Toolbar polish** — Action buttons use `Label` for macOS "Icons and Text" mode. Search bar relocated from toolbar to breadcrumb bar (avoids system wrapper bubble). Sidebar navigation title hidden. Body split into `mainContent` + `browsePickerSheet` to fix Swift type-checker timeout.
- **Toolbar architecture refactor** — Toolbar lifted from `S3ObjectBrowserView` to parent views (`S3ModuleView`, `S3BrowserWindow`) via shared `S3ToolbarState` (ObservableObject two-way bridge) + `S3Toolbar` (reusable `ToolbarContent`). Browser view syncs display state upward (`onChange`) and handles actions via `pendingAction` enum. Removed `ToolbarDisplayModeSaver` (custom KVO + UserDefaults hack) and duplicate placeholder toolbar. Each future module (SQS, SNS) can define its own toolbar independently.
- **Toolbar display mode persistence — skipped** — Attempted: `toolbar(id:)` with `CustomizableToolbarContent` (doesn't persist display mode, only item customization), KVO on `NSToolbar.displayMode` via NSViewRepresentable with `viewDidMoveToWindow` + window.toolbar observation (observer never reliably attaches — SwiftUI manages toolbar lifecycle opaquely). Would likely require NSWindowController or full AppKit toolbar ownership. Low priority — user can change display mode per session.
- **Window & layout defaults** — Main WindowGroup `.defaultSize(width: 1100, height: 700)` for proper first-launch sizing. Sidebar `navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)` for consistent proportions.
- **Human-readable file sizes** — `S3Object.formattedSize` computed property using `ByteCountFormatter` with `.file` count style (e.g., "4.2 MB"). Used consistently in object browser table, metadata view, folder metadata view, and folder picker.

## Verification

After each phase: `swift build` must pass. Manual test against running LocalStack.
