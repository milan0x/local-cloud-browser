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

## Phase 8: Duplicate Object

**Goal:** Right-click an object → "Duplicate" to create a copy in the same folder using macOS Finder naming convention. Uses S3 native server-side copy (`x-amz-copy-source` header) — no data downloaded or re-uploaded.

**Priority:** Low — convenience feature for testing workflows.

**Verified:** LocalStack Community supports `x-amz-copy-source` (tested: `PUT` with header returns `<CopyObjectResult>`, same ETag, content type preserved, HTTP 200).

**Files:**
- `LocalStackClient.swift` — Add `headers: [String: String] = [:]` parameter to `s3Request()` and `executeRequest()`. In `executeRequest()`, apply custom headers to the `URLRequest` after the existing content-type logic. This is a small, backwards-compatible change (default empty dict).
- `S3Service.swift` — Add `duplicateObject(bucket:key:)` that: (1) computes the new key name using Finder naming convention, (2) checks for collisions, (3) sends a `PUT` with `x-amz-copy-source` header via the updated `s3Request()`. Also add `duplicateFolder(bucket:prefix:)` for folder duplication.
- `S3ObjectBrowserView.swift` — Add "Duplicate" to right-click context menu for files and folders. Single-item only (no multi-select duplicate). Disabled in read-only mode.

**Naming convention — macOS Finder style:**
- `report.json` → `report copy.json` → `report copy 2.json` → `report copy 3.json`
- `Makefile` (no extension) → `Makefile copy` → `Makefile copy 2`
- `archive.tar.gz` (compound extension) → `archive copy.tar.gz` → `archive copy 2.tar.gz`
- `my-folder/` → `my-folder copy/` → `my-folder copy 2/`

**Name generation logic:**
1. Split the key's filename at the **first** `.` to get `(stem, extension)`. This handles compound extensions: `archive.tar.gz` → stem `archive`, extension `.tar.gz`. For no extension: stem is the full name, extension is empty.
2. Proposed name = `{stem} copy.{extension}` (or `{stem} copy` if no extension).
3. Check if that key already exists in the current prefix by scanning the already-loaded `objects` array — do NOT make an extra `HEAD` request. The browser already has the full object list for the current page.
4. If it exists, try `{stem} copy 2`, `{stem} copy 3`, etc., up to a reasonable limit (99).
5. If all 99 names are taken, show an error. This will never happen in practice.

**Implementation approach:**
1. **Server-side copy for files:** Single `PUT` request with empty body + `x-amz-copy-source: /{bucket}/{encodedKey}` header. The `x-amz-copy-source` value must be URL-encoded (percent-encode the key). Content type is preserved automatically by S3 — no need to read it first.
2. **Folder duplication:** List all objects under the folder prefix (`listAllObjects`), then server-side copy each one, rewriting the prefix from `original/` to `original copy/`. Sequential loop, same as folder move.
3. **Context menu placement:** Add "Duplicate" after "Move..." in the right-click context menu. Only show for single selection (when `selectedRowIDs.count <= 1` or on the right-clicked item). Dimmed/disabled for multi-select — duplicating many objects at once is confusing and rarely needed.
4. **After duplication:** Call `loadObjects(force: true)` to refresh the browser. The new copy will appear in the list.

**Things to watch for — DO NOT skip these:**

- **`x-amz-copy-source` URL encoding:** The source key MUST be percent-encoded in the header value. Keys with spaces, special characters, or Unicode will break if passed raw. Use `key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)`. Tested: `item.json` works, but keys like `random name/Screenshot 2026-01-25 at 21.52.30.png` will fail without encoding.
- **Collision check uses local data only:** Check against the already-loaded `objects` array and `folders` array in the browser view. Do NOT make a `HEAD` request per candidate name — that's N network round-trips for no reason. The object list is already in memory. Edge case: if the list is paginated and the collision is on a different page, we might miss it. This is acceptable — S3 `PUT` silently overwrites, so worst case a duplicate overwrites an existing object on another page. For a dev tool, this risk is negligible.
- **Don't duplicate the `..` parent row:** Guard against the `".."` sentinel ID in the context menu handler, same as delete/move.
- **Compound extensions:** Do NOT split at the last `.` — that turns `archive.tar.gz` into `archive.tar copy.gz` which is wrong. Split at the first `.` so the full extension is preserved: `archive copy.tar.gz`.
- **Folder markers:** When duplicating a folder, also copy the zero-byte folder marker object (`prefix/` → `prefix copy/`). Without this, the duplicated folder won't appear until files are inside it.
- **Read-only mode:** "Duplicate" must be `.disabled(appState.isReadOnly)` in the context menu, consistent with all other mutating actions.
- **`executeRequest` header addition:** When adding the `headers` parameter, apply custom headers AFTER the content-type logic so they can't accidentally override Content-Type. Loop: `for (key, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: key) }`.
- **Existing `copyObject` in S3Service:** The current `copyObject()` uses GET+PUT (downloads then re-uploads). Do NOT modify it — other code (`moveObject`, `moveObjectToBucket`) depends on it. Add a new `duplicateObject()` method that uses the native header approach. Optionally, add a lower-level `s3CopyNative()` that uses the header, and migrate `copyObject` later as a separate refactor.
- **Error handling:** Show `serviceError` alert if the copy fails. Common failure: source object deleted between listing and copy attempt (race condition). Unlikely in a dev tool, but handle gracefully.

---

## Implementation Order

Phases are independent and ordered by complexity (simplest first):
1. ~~Create Folder~~ ✅ (also includes move, back/forward, parent row, folder picker revamp)
2. ~~Multi-Select Delete~~ ✅ (Set-based selection, bulk delete, adapted context menus)
3. ~~Copy Key / S3 URI~~ ✅ (Copy Key, Copy S3 URI, JSON array for multi-select, buckets + objects)
4. ~~Quick Look Preview~~ ✅ (QLPreviewPanel, streaming download, size limit settings, eye button, spacebar)
5. Force Delete Bucket — new service logic + two-step confirmation flow
6. ~~S3 Search & Filter~~ ✅ (reusable SearchBarView, current-folder filter only)
7. Folder Upload — drag-and-drop + NSOpenPanel, recursive enumerate, progress indicator, junk file filter
8. Duplicate Object — right-click "Duplicate", server-side copy via `x-amz-copy-source`, Finder naming, collision check

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
