# S3 Improvements Plan — 6 Phases

## Phase 1: Create Folder + Folder UX ✅

**Goal:** Allow users to create "folders" (zero-byte keys ending in `/`) in the current prefix, with full file-browser navigation.

**Completed:**
- [x] Create folder: toolbar button (folder.badge.plus), sheet with validation (format + name collision detection), `S3Service.createFolder()`
- [x] Create bucket collision detection: validates name against existing buckets, disables "Create" button with red warning
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

## Phase 5: Empty Bucket Before Delete (Force Delete) ✅

**Goal:** When deleting a non-empty bucket, offer to empty it first then delete.

**Completed:**
- [x] `S3Service.emptyBucket(bucket:)` — lists all objects via `listAllObjects` (handles pagination) and deletes them all via `deleteObjects`
- [x] `S3Service.forceDeleteBucket(bucket:)` — calls `emptyBucket` then `deleteBucket`
- [x] `deleteBuckets()` catches `BucketNotEmpty` error code and triggers force-delete alert instead of generic error
- [x] Force-delete alert: title "Bucket Not Empty" / "Buckets Not Empty", TextField requiring user to type "delete" to confirm
- [x] Invalid confirmation (not "delete") re-shows the alert
- [x] `performForceDelete()` — loops through targets, calls `forceDeleteBucket`, handles errors via `serviceError` alert
- [x] Progress overlay: semi-transparent background with `ProgressView("Deleting...")` while force deleting, entire view disabled
- [x] Auto-refresh guard: skips refresh when force-delete alert is showing or force delete is in progress
- [x] Multi-bucket support: if multiple selected buckets are non-empty, all collected into `forceDeleteBuckets` for single confirmation
- [x] Read-only mode: no changes needed — delete button already disabled, force-delete flow unreachable

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

## Phase 7: Folder Upload (Drag-and-Drop + Toolbar)

**Goal:** Allow uploading entire folders into S3, preserving directory structure. Supports both drag-and-drop from Finder and the toolbar Upload button.

**Priority:** Low — polish feature, not blocking other work. Implement after SQS/SNS modules or Force Delete Bucket.

**Current problem:** Dropping a folder from Finder onto the object browser **silently fails**. `Data(contentsOf:)` cannot read a directory, so the upload errors out with no user feedback. This must be fixed regardless — either by supporting folder upload or by showing a clear error.

**Files:**
- `S3ObjectBrowserView.swift` — Modify `.onDrop` handler (line ~431) to detect folders and recursively upload. Modify `uploadFile()` to allow directory selection via `NSOpenPanel`.
- `S3Service.swift` — No changes needed; reuse existing `putObject(bucket:key:data:contentType:)` for each file.

**Implementation approach:**
1. **Detect folders in drop handler:** Check `url.hasDirectoryPath` on each URL from `NSItemProvider`. Separate into file URLs and folder URLs.
2. **Enumerate folder contents:** Use `FileManager.default.enumerator(at:url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])` to recursively walk all files.
3. **Preserve structure:** For each file, compute relative path from the folder root. Prepend `currentPrefix + folderName/` to create the S3 key. Example: dropping `photos/` containing `2024/cat.jpg` into prefix `data/` creates key `data/photos/2024/cat.jpg`.
4. **Upload files sequentially:** Call `putObject` for each file with correct key and content type.
5. **NSOpenPanel support:** Change `canChooseDirectories` from `false` to `true` in `uploadFile()`. Detect whether the user selected a file or directory and handle accordingly.
6. **Empty subdirectories:** Create zero-byte folder marker objects (key ending in `/`) so empty subdirectories appear in the browser. This is consistent with how "Create Folder" already works.

**Things to watch for — DO NOT skip these:**

- **macOS junk files — FILTER OUT:** Skip `.DS_Store`, `._*` (AppleDouble resource forks), `.Spotlight-V100`, `.Trashes`, `__MACOSX`, `Thumbs.db`. These are invisible metadata files macOS creates inside folders. Uploading them to S3 pollutes the bucket with useless objects. Use a hardcoded skip-list checked against each filename.
- **Symbolic links — DO NOT FOLLOW:** `FileManager.enumerator` follows symlinks by default. A symlink pointing to a parent directory creates an infinite loop that will hang the app or exhaust memory. Pass `.skipsHiddenFiles` is NOT sufficient (symlinks aren't hidden). Either: (a) check `resourceValues.isSymbolicLink` and skip, or (b) use `enumerator(at:, includingPropertiesForKeys:, options: [])` and manually check each item. Safest: skip all symlinks entirely.
- **Large folders — SHOW PROGRESS:** Uploading 100+ files sequentially can take a while. Must show a progress indicator: "Uploading 12 of 47 files..." as an overlay or inline status. Without this, the user thinks the app froze. Consider a cancel button for very large uploads.
- **`Data(contentsOf:)` memory — WATCH FILE SIZES:** Current upload reads entire file into memory. For a folder with many large files, this is fine one-at-a-time (sequential loop frees each `Data` after upload). Do NOT load all files into memory at once. Keep the sequential loop pattern.
- **Error handling — DON'T STOP ON FIRST ERROR:** If file 5 of 20 fails, continue uploading the rest. Collect failures and show a summary at the end: "Uploaded 18 of 20 files. 2 failed: [names]." Stopping on first error wastes all the successful uploads and frustrates the user.
- **Read-only mode:** Folder upload must be blocked when `appState.isReadOnly` is true, same as file upload. The `.onDrop` handler already guards this.
- **Sandboxing:** App is currently NOT sandboxed (SPM build, no entitlements). `FileManager.enumerator` has unrestricted access. If sandboxing is ever added, dropped folder URLs would need `url.startAccessingSecurityScopedResource()` / `url.stopAccessingSecurityScopedResource()` bracketing.
- **Content type detection:** Use existing pattern — `UTType(filenameExtension:)?.preferredMIMEType ?? "application/octet-stream"` for each file. Do not try to detect content type from file contents.

---

## Phase 8: Duplicate Object ✅

**Goal:** Right-click an object → "Duplicate" to create a copy in the same folder using macOS Finder naming convention. Uses S3 native server-side copy (`x-amz-copy-source` header) — no data downloaded or re-uploaded.

**Completed:**
- [x] `LocalStackClient.swift` — Added `headers: [String: String] = [:]` parameter to `s3Request()` and `executeRequest()`, applied after content-type logic
- [x] `S3Service.swift` — `duplicateObject()` and `duplicateFolder()` using server-side copy via `x-amz-copy-source` header
- [x] `S3ObjectBrowserView.swift` — "Duplicate" in right-click context menu for single files and folders, disabled in read-only mode
- [x] Finder naming: `name copy.ext` → `name copy 2.ext` etc., collision check against loaded objects/prefixes (no extra HEAD requests)

---

## Phase 9: Server-Side Copy Upgrade + Rename + Download as ZIP ✅

**Goal:** Upgrade all move/copy operations to use S3 server-side copy (no download/re-upload), add rename for files and folders, add folder download as ZIP.

**Completed:**

### Server-Side Copy Upgrade
- [x] `S3Service.serverSideCopy()` — General-purpose server-side copy between any two buckets using `x-amz-copy-source` header
- [x] `duplicateObject()` now delegates to `serverSideCopy` (same bucket)
- [x] `moveObject()` upgraded from HEAD+GET+PUT+DELETE to `serverSideCopy`+DELETE
- [x] `copyObject()` upgraded from HEAD+GET+PUT to `serverSideCopy` (cross-bucket capable)
- [x] All downstream methods (`moveObjects`, `moveFolder`, `moveObjectToBucket`, `moveFolderToBucket`) automatically benefit

### Rename
- [x] `S3Service.renameObject()` — server-side copy + delete within same bucket
- [x] `S3Service.renameFolder()` — copy ALL objects first, then delete ALL originals (safer: originals intact if copy fails midway)
- [x] Context menu "Rename" for single files (after Metadata) and single folders (after Copy as AWS JSON divider)
- [x] Rename sheet: title, current name display, text field pre-filled with current name, validation (not empty, not same as current, no `/`, no name collision)
- [x] Collision detection: validates new name against existing files/folders in the current directory, disables "Rename" button and shows red warning when name already exists — prevents silent S3 PUT overwrite
- [x] Disabled in read-only mode, not shown for `..` parent row or multi-select
- [x] `itemToRename` added to `anySheetOpen` to suppress auto-refresh during rename
- [x] Standard error handling via `serviceError` alert

### Download Folder as ZIP
- [x] `S3Service.downloadFolderAsZip()` — lists all objects, downloads to temp directory preserving relative paths, zips with `/usr/bin/ditto -c -k --sequesterRsrc`, returns ZIP URL
- [x] Zero-byte folder markers (keys ending in `/` with size 0) filtered out before download
- [x] Returns `nil` for empty folders → triggers "Empty Folder" alert
- [x] Progress callback: `(current: Int, total: Int)` called after each file download
- [x] Context menu "Download as ZIP" on single folders (after "Open in New Window")
- [x] Status bar progress: spinner + "Downloading folder... (12/47)" in the bottom bar between item count and pagination
- [x] NSSavePanel with default filename `foldername.zip`
- [x] Temp directory + ZIP cleaned up after save/cancel
- [x] Disabled while another folder download is in progress
- [x] `folderDownloadProgress` added to `anySheetOpen` to suppress auto-refresh during download

### Column Label
- [x] "Date Added" column renamed to "Date Modified" — more accurate since S3 `LastModified` reflects the last write time (upload, copy, rename)

### Delete Button Safety
- [x] Bucket delete button disabled when objects are selected in the browser — prevents accidental bucket deletion when user meant to delete objects
- [x] Bucket delete tooltip changes to "Click on the bucket you want to delete — objects are currently selected" when objects are selected
- [x] Toolbar (object) delete button colored red when enabled, gray when disabled — visually signals destructive action
- [x] `PaneClickDetector` (NSViewRepresentable) on bucket list background detects clicks via `NSEvent.addLocalMonitorForEvents` and clears browser object selection through `S3ToolbarState.clearSelectionTrigger`
- [x] Clicking any bucket (including already-selected) deselects objects in the browser, enabling the bucket delete button
- [x] `S3BucketListView` now takes `@ObservedObject toolbarState: S3ToolbarState` instead of a plain `hasObjectSelection` bool

**Context menu order (single file):**
1. Download / Quick Look
2. Copy (to app clipboard)
3. Copy Key / Copy S3 URI / Copy as AWS JSON
4. Divider
5. Metadata / Rename / Move... / Move to / Duplicate
6. Divider
7. Delete

**Context menu order (single folder):**
1. Open / Folder Info / Open in New Window
2. Download as ZIP
3. Copy (to app clipboard)
4. Divider
5. Copy Key / Copy S3 URI / Copy as AWS JSON
6. Divider
7. Rename / Move... / Move to / Duplicate
8. Divider
9. Paste Here
10. Divider
11. Delete Folder

**Context menu order (multi-select):**
1. Copy N Items (to app clipboard)
2. Divider
3. Copy N Paths / Copy N S3 URIs / Copy as AWS JSON
4. Divider
5. Move N Items... / Move to
6. Divider
7. Delete N Items

**Context menu order (empty area):**
1. Create Folder / Upload File
2. Divider
3. Paste

---

## Phase 10: Intra-App Copy/Paste ✅

**Goal:** Clipboard-based copy/paste for S3 objects and folders using server-side copy — no data leaves the server.

**Completed:**
- [x] `S3Clipboard` model — `sourceBucket`, `objectKeys`, `folderPrefixes`, stored on `AppState` for app-wide sharing across views and windows
- [x] `S3Service.copyFolder()` — recursive server-side copy preserving relative paths, supports cross-bucket
- [x] "Copy" context menu item for single files (after Quick Look), single folders (after Download as ZIP), and multi-select ("Copy N Items")
- [x] "Paste" on empty-area right-click (after Upload File) — pastes into current prefix
- [x] "Paste Here" on folder right-click (before Delete Folder) — pastes directly into that folder without navigating
- [x] Dynamic labels: "Paste (3 Items)", "Paste Here (1 Item)" — shows clipboard content count
- [x] Disabled when clipboard is empty, in read-only mode, or during active paste
- [x] Clipboard not cleared on paste (standard OS behavior — paste multiple times)
- [x] Cross-bucket: copy in bucket A, navigate to bucket B, paste — works via `serverSideCopy`

**Design decisions:**
- Keyboard shortcuts: Cmd+C (copy to S3 clipboard), Cmd+V (paste from S3 clipboard), Cmd+Backspace (delete selected items). Uses `FocusedValues` + `CommandGroup(replacing: .pasteboard)` with `NSApp.keyWindow?.firstResponder is NSTextView` check to fall through to standard text behavior when a text field is focused. Works in both main window and S3 browser windows.
- No visual clipboard indicator (dynamic context menu label is sufficient)
- Paste collisions: collision warning alert shown before paste if destination contains same-named items (see Phase 11)

---

## Phase 11: Collision Detection ✅

**Goal:** Prevent silent data loss from S3's PUT-overwrites-existing semantics. When a user creates, renames, moves, or pastes items, warn if something with the same name already exists at the destination.

**Problem:** S3 has no concept of "file already exists" — every PUT silently replaces whatever was at that key. Combined with move (which deletes the source after copy), this means a careless move can permanently destroy destination files with zero warning. The same risk applies to paste, rename, create folder, and create bucket.

**Completed:**

### Inline validation (preventive — blocks the action)
These check against locally loaded data (no extra API call) and disable the action button with a red warning message when a collision is detected:

- [x] **Rename collision detection** — rename sheet validates new name against existing files and folders in the current directory. Compares `renameText` against `objects.map(\.displayName)` and `prefixes.map(\.displayName)`. Disables "Rename" button and shows red text: "An item named "X" already exists in this folder."
- [x] **Create folder collision detection** — create folder sheet validates name against existing folders and files. Uses same local comparison. Disables "Create" button with same red warning.
- [x] **Create bucket collision detection** — create bucket sheet validates name against existing buckets loaded in the bucket list. Disables "Create" button with red warning: "A bucket named "X" already exists."
- [x] **Duplicate collision avoidance** — `duplicateName()` generates `name copy.ext` / `name copy 2.ext` etc., checking against loaded objects/prefixes. No collision possible — always finds a unique name.

### Async warning (confirmatory — user decides)
These make an async `listObjects` call to the destination folder before executing, because the destination may not be the current folder (move to parent, move to subfolder, move to another bucket, paste into folder):

- [x] **Move collision warning** — `requestMove()` wraps `performMove()`. Before executing, calls `checkCollisions()` which lists the destination folder via `service.listObjects()` and compares incoming file/folder names against existing items. If collisions found, shows native `.alert()` with "Stop" / "Replace" buttons.
- [x] **Cross-bucket move collision warning** — `requestMoveToBucket()` wraps `performMoveToBucket()`. Same pattern — lists the destination prefix in the target bucket before moving.
- [x] **Paste collision warning** — `requestPaste(into:)` wraps `performPaste(into:)`. Checks destination folder (current prefix or specific folder for "Paste Here") before copying.

### Implementation details

**`checkCollisions()` method:**
```
checkCollisions(bucket:destinationPrefix:incomingFileNames:incomingFolderNames:) -> [String]
```
- Calls `service.listObjects(bucket:prefix:)` on the destination
- Builds sets of existing file names (`result.objects.map(\.displayName)`) and folder names (`result.commonPrefixes.map(\.displayName)`)
- Returns sorted intersection of incoming names vs. existing names
- Returns empty array on error (fail-safe — proceeds without warning rather than blocking the operation)

**Collision alert (shared by all three `request*` methods):**
- Title: "N Items Already Exist" / "1 Item Already Exists"
- Message lists all colliding names, then explains S3 merge behavior:
  - Matching items will be replaced
  - Other existing items will remain untouched
  - New items will be added
- Buttons: "Stop" (cancel, `.cancel` role) and "Replace" (proceed, `.destructive` role)
- State: `@State collisionItems: [String]` (names) + `@State collisionAction: (() -> Void)?` (deferred execution closure)
- Alert placed on `mainContent` (not `body`) to avoid Swift type-checker timeout

**Callers updated (9 locations):**
| Caller | Was | Now |
|---|---|---|
| Move sheet "Move" button | `performMove()` | `requestMove()` |
| Move sheet `.onSubmit` | `performMove()` | `requestMove()` |
| `moveToMenu` ".." and subfolder buttons | `performMove()` | `requestMove()` |
| `folderMoveToMenu` ".." and subfolder buttons | `performMove()` | `requestMove()` |
| `mixedMoveToMenu` ".." and subfolder buttons | `performMove()` | `requestMove()` |
| Browse picker same-bucket callback | `performMove()` | `requestMove()` |
| Browse picker cross-bucket callback | `performMoveToBucket()` | `requestMoveToBucket()` |
| "Move to Bucket" sheet "Move" button | `performMoveToBucket()` | `requestMoveToBucket()` |
| Empty area "Paste" (2 locations) | `performPaste()` | `requestPaste()` |
| Folder "Paste Here" | `performPaste(into:)` | `requestPaste(into:)` |

**Design decisions:**
- Used `.alert()` (NSAlert) for the collision warning — consistent with all other confirmation dialogs in the app (delete objects, delete folders, delete buckets). `.alert()` is a centered modal that forces the user to stop and read, appropriate for a "data will be overwritten" warning.
- SwiftUI `.alert()` does not expose `NSAlert.alertStyle` — always renders with the app icon, not the yellow warning triangle. To get the warning icon would require dropping to AppKit (`NSAlert` directly), which breaks the SwiftUI pattern. Accepted trade-off.
- "Stop" / "Replace" button labels chosen over "Cancel" / "Overwrite" — "Stop" is clearer than "Cancel" (the operation hasn't started), "Replace" is less alarming than "Overwrite" while still conveying the consequence.
- Fail-safe on error: if `listObjects` fails during collision check, returns empty (no collisions) and proceeds with the operation. Rationale: the move/paste will likely fail anyway with its own error, and blocking the user because of a transient listing failure is worse than proceeding.
- No collision check for duplicate — `duplicateName()` already generates unique names algorithmically, so collisions are impossible.

**Files modified:**
- `S3ObjectBrowserView.swift` — `checkCollisions()`, `requestMove()`, `requestMoveToBucket()`, `requestPaste()`, collision alert state + `.alert()`, all 9 caller updates

---

## Implementation Order

Phases are independent and ordered by complexity (simplest first):
1. ~~Create Folder~~ ✅ (also includes move, back/forward, parent row, folder picker revamp)
2. ~~Multi-Select Delete~~ ✅ (Set-based selection, bulk delete, adapted context menus)
3. ~~Copy Key / S3 URI~~ ✅ (Copy Key, Copy S3 URI, JSON array for multi-select, buckets + objects)
4. ~~Quick Look Preview~~ ✅ (QLPreviewPanel, streaming download, size limit settings, eye button, spacebar)
5. ~~Force Delete Bucket~~ ✅ (BucketNotEmpty detection, typed "delete" confirmation, emptyBucket + forceDeleteBucket, progress overlay)
6. ~~S3 Search & Filter~~ ✅ (reusable SearchBarView, current-folder filter only)
7. Folder Upload — drag-and-drop + NSOpenPanel, recursive enumerate, progress indicator, junk file filter
8. ~~Duplicate Object~~ ✅ (server-side copy via `x-amz-copy-source`, Finder naming, collision check)
9. ~~Server-Side Copy + Rename + Download ZIP~~ ✅ (all move/copy upgraded to server-side, rename files/folders with collision detection, download folder as ZIP, delete button safety)
10. ~~Intra-App Copy/Paste~~ ✅ (clipboard-based copy/paste via context menus, server-side copy, cross-bucket, app-wide clipboard on AppState)
11. ~~Collision Detection~~ ✅ (inline validation for rename/create folder/create bucket, async collision warning for move/paste with "Stop"/"Replace" alert)

## Completed (outside phases)
- **Auto-refresh extraction** — reusable `AutoRefreshManager` (on `AppState`, injected as `@EnvironmentObject`), `AutoRefreshIndicatorView` (countdown in breadcrumb bar), `AutoRefreshMenuView` (single toolbar menu with Refresh Now + interval picker, `.menuStyle(.borderlessButton)` + `.fixedSize()` for compact icon). Internal Task-based timer, `refreshTrigger` pattern. Both S3 bucket list and object browser auto-refresh. Settings view uses `@EnvironmentObject` directly.
- **Bucket list header layout** — Rearranged: Buckets label → countdown → spacer → + (create, accent-colored) → refresh menu → trash (always visible, disabled until selection). Pane width increased from 220pt to 260pt to prevent layout cramping when delete button appears.
- **Native delete dialogs** — All delete confirmations (objects, folders, buckets) use `.alert()` (native macOS NSAlert) instead of `.confirmationDialog()` or custom sheets. Multi-delete lists each item name on separate lines. Removed the large custom `folderDeleteSheet` view.
- **Right-click context menus on empty areas** — Object browser empty state: right-click shows "Create Folder" + "Upload File". Bucket list empty state: right-click shows "Create Bucket". Uses `.contentShape(Rectangle())` for full-area hit detection. Also added "Create Bucket" to per-row bucket context menu.
- **SearchBarView component** — Reusable `Navigation/SearchBarView.swift` with generic `TrailingContent`, fixed 200pt width, convenience init for no trailing content (`EmptyView`). Used by S3 object browser; ready for future SQS/SNS/Secrets Manager modules.
- **S3 global region indicator** — Region badge in toolbar shows "Global" (dimmed, 50% opacity) when viewing S3 instead of the region name. Tooltip on hover: "S3 buckets are global on LocalStack, not region-specific". Bucket list header also shows small "Global" caption in `.caption2` + `.tertiary`. Other modules still show the actual region.
- **Toolbar polish** — Action buttons use `Label` for macOS "Icons and Text" mode. Search bar relocated from toolbar to breadcrumb bar (avoids system wrapper bubble). Sidebar navigation title hidden. Body split into `mainContent` + `browsePickerSheet` to fix Swift type-checker timeout.
- **Toolbar architecture refactor** — Toolbar lifted from `S3ObjectBrowserView` to parent views (`S3ModuleView`, `S3BrowserWindow`) via shared `S3ToolbarState` (ObservableObject two-way bridge) + `S3Toolbar` (reusable `ToolbarContent`). Browser view syncs display state upward (`onChange`) and handles actions via `pendingAction` enum. Removed `ToolbarDisplayModeSaver` (custom KVO + UserDefaults hack) and duplicate placeholder toolbar. Each future module (SQS, SNS) can define its own toolbar independently.
- **Searchable region picker** — Replaced free-text region `TextField` in S3 create bucket dialog and connection profile editor with a validated region picker. Three new files: `App/AWSRegion.swift` (static model with 39 AWS regions — 34 standard, 2 GovCloud, 2 China, 1 Sovereign — with `isValid()` O(1) Set lookup and `find()` by code), `Navigation/SearchableDropdown.swift` (reusable popover-based dropdown with filter-as-you-type matching both label and description, checkmark + accent highlight on selected item, auto-scroll to selection on open, max 260pt scrollable list), `Navigation/AWSRegionPicker.swift` (thin wrapper mapping `AWSRegion.allRegions` to `SearchableDropdownItem` array with label = region code, description = display name). `S3CreateBucketView.swift` — replaced `TextField("Region (e.g. us-east-1)")` with `AWSRegionPicker(regionCode: $region)`, increased VStack spacing from 4pt to 8pt for visual breathing room above the info label. `ConnectionProfileEditorView.swift` — replaced `TextField("Region")` with `LabeledContent("Region") { AWSRegionPicker(regionCode: $region) }` for proper Form alignment. `selectedID` binding only written on item click — no free text accepted. `SearchableDropdown` is generic and reusable for any future dropdown needs.
- **Toolbar display mode persistence — skipped** — Attempted: `toolbar(id:)` with `CustomizableToolbarContent` (doesn't persist display mode, only item customization), KVO on `NSToolbar.displayMode` via NSViewRepresentable with `viewDidMoveToWindow` + window.toolbar observation (observer never reliably attaches — SwiftUI manages toolbar lifecycle opaquely). Would likely require NSWindowController or full AppKit toolbar ownership. Low priority — user can change display mode per session.
- **Window & layout defaults** — Main WindowGroup `.defaultSize(width: 1100, height: 700)` for proper first-launch sizing. Sidebar `navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)` for consistent proportions.
- **Human-readable file sizes** — `S3Object.formattedSize` computed property using `ByteCountFormatter` with `.file` count style (e.g., "4.2 MB"). Used consistently in object browser table, metadata view, folder metadata view, and folder picker.
- **Delete button safety** — Bucket delete (trash icon in bucket list header) disabled when objects are selected in the browser, with tooltip "Click on the bucket you want to delete — objects are currently selected". Toolbar object delete button colored red when enabled. `PaneClickDetector` (NSViewRepresentable with `NSEvent.addLocalMonitorForEvents`) on bucket list pane clears browser object selection on any click, ensuring only one delete scope is active at a time.

## Future Considerations

- **"Copy to" context menu** — A "Copy to" submenu mirroring the existing "Move to" logic: quick options for parent folder (`..`) and visible subfolders, plus a "Browse..." option opening the folder picker for cross-bucket/arbitrary destination selection. Uses `serverSideCopy` (no download/re-upload). Difference from intra-app copy/paste: "Copy to" is a single-action shortcut (right-click → pick destination → done) vs. the two-step copy-then-paste workflow. Same collision detection pattern as move (`checkCollisions()` before executing). Supports single files, single folders (recursive), and multi-select.
- **Folder upload** — Upload entire folders via drag-and-drop from Finder and toolbar Upload button (NSOpenPanel with `canChooseDirectories: true`). Recursively enumerate folder contents with `FileManager.enumerator`, preserve directory structure as S3 key prefixes, create zero-byte folder markers for empty subdirectories. Must filter macOS junk files (`.DS_Store`, `._*`, `__MACOSX`), skip symbolic links (prevent infinite loops), show upload progress ("Uploading 12 of 47 files..."), continue on individual file errors (show summary at end). Currently dropping a folder shows a "Folder Upload Not Supported" alert. See Phase 7 for full implementation details.

## Verification

After each phase: `swift build` must pass. Manual test against running LocalStack.
