# S3 Gap Analysis: S3BrowserApp vs LocalCloudBrowser

**Date:** 2026-04-22
**Status:** In Progress

---

## Legend
- [x] Already implemented in LocalCloudBrowser
- [ ] **MISSING** — needs implementation
- [~] Partial — exists but incomplete compared to S3BrowserApp

---

## 1. NETWORKING & INFRASTRUCTURE

### Retry System
- [x] RetryPolicy with exponential backoff + jitter (`RetryPolicy.swift`)
- [x] RetryExecutor with `withRetry()` generic function (`RetryExecutor.swift`)
- [x] RetryAttempt model for UI state
- [x] Retryable status codes: 500, 502, 503, 504 + network errors
- [x] Task cancellation support in retry loop
- [ ] **MISSING: RetryBannerView** — S3BrowserApp has a dedicated UI banner showing "Retrying (X/Y)..." with cancel button. LocalCloudBrowser has the retry infrastructure but no visual banner for the user.

### Request Signing
- [x] SigV4Signer with SHA256 payload hashing
- [x] RequestSigningContext (Sendable) for background signing
- [x] UNSIGNED-PAYLOAD for streaming uploads
- [x] Session token support (x-amz-security-token)
- [x] Virtual-hosted-style URL support
- [x] Path-style URL support (LocalStack, MinIO)
- [x] RFC 3986 path encoding in RequestSigningContext
- [x] Content-MD5 header for parts

### URLSession Configuration
- [~] **PARTIAL: Custom URLSession** — `AppState` creates an ephemeral URLSessionConfiguration (line 73) but `S3Service.downloadObjectToFile` uses `URLSession.shared` (line 88), `S3QuickLookManager` uses `URLSession.shared` (line 49). Not all S3 operations route through the custom session. No custom timeouts or connection pooling config.

### Connection Monitoring
- [x] ConnectionLostBanner view (used across all modules)
- [x] Health check system in AppState
- [x] Auto-reconnection on health check success
- [ ] **MISSING: Credential expiration banner** — S3BrowserApp shows a "Session token may have expired" banner with "Update Credentials" button. LocalCloudBrowser parses `ExpiredToken` in ServiceError but has no dedicated UI banner for it.

---

## 2. UPLOADS

### Single File Upload
- [x] Upload via toolbar button (file picker)
- [x] Upload via drag & drop (files and folders)
- [x] Automatic content-type detection via UTType
- [x] Drop target overlay visual feedback

### Multipart Upload
- [x] StreamingUploader with single PUT (≤5MB) and multipart (>5MB)
- [x] ByteAccumulator for thread-safe progress tracking
- [x] Concurrent part uploads (max 4)
- [x] Auto-abort on failure/cancellation
- [x] Content-MD5 per part
- [x] FileHandle-based sequential chunking (memory-safe)
- [~] **PARTIAL: Multipart threshold mismatch** — S3Service uses 20MB threshold (line 9) while StreamingUploader handles >5MB. The S3Service `uploadObject()` method has its own multipart implementation at 20MB that duplicates StreamingUploader's logic. S3BrowserApp uses 5MB consistently. Medium files (5-20MB) use single PUT in S3Service's path but multipart in StreamingUploader's path.

### Transfer Queue
- [x] TransferManager with per-bucket tracking
- [x] Queue position calculation (filesAhead, bucketsAhead)
- [x] Pending/active/completed/failed/cancelled states
- [x] Per-item cancellation
- [x] Batch result notifications
- [x] TransferToolbarButton with badge count
- [x] TransferPopoverView showing transfer list
- [x] Transfer pill overlay in object browser

### Upload Progress
- [x] Per-file progress via ByteAccumulator
- [x] Cumulative progress percentage
- [~] **PARTIAL: Progress callback only reports bytes uploaded** — same as S3BrowserApp, no total bytes in callback signature. UI can show bytes but not percentage without knowing file size separately.

---

## 3. DOWNLOADS

### Single File Download
- [x] Download via action button in row
- [x] Download via context menu
- [x] Stream to file via URLSession.download
- [ ] **MISSING: Download progress tracking** — `downloadObjectToFile` (S3Service.swift:86-105) streams to file but has NO progress callback. User gets no feedback during large file downloads. S3BrowserApp has `downloadObject(bucket:key:destinationURL:progress:)` with progress callback.

### Folder Download
- [x] Download as ZIP via context menu / toolbar
- [x] Filters zero-byte folder markers
- [x] Progress callback (current/total files)
- [x] Save dialog before cleanup
- [x] Uses `/usr/bin/ditto` for zipping

### In-Memory Download
- [x] `getObject()` returns Data for small files (used by Quick Look, metadata)

---

## 4. QUICK LOOK / PREVIEW

- [x] Space key triggers preview
- [x] Size limit checking (user-configurable)
- [x] Hard cap at 300MB
- [x] "Preview Anyway" for files over user limit but under hard cap
- [x] PreviewCache with SHA-256 keying, LRU eviction, ETag validation
- [x] Cache management in Settings (toggle, size limit, clear)
- [ ] **MISSING: Download progress during Quick Look** — S3BrowserApp shows a download progress overlay while fetching the preview file. LocalCloudBrowser's `S3QuickLookManager` downloads without progress indication.

---

## 5. BUCKET OPERATIONS

### Bucket List
- [x] List buckets with creation dates
- [x] Search/filter (appears when >5 buckets)
- [x] Sorting by creation date (newest first)
- [x] Multi-select support
- [x] Session restore (last selected bucket)

### Bucket Context Menu
- [x] Open in New Window
- [x] Copy Name / Copy S3 URI
- [x] Copy N Names / Copy N S3 URIs (multi-select)
- [x] Create Bucket
- [x] Delete / Delete N Buckets

### Bucket Empty State
- [x] "No buckets" empty state with icon
- [x] Context menu on empty state to Create Bucket

### Create Bucket
- [x] Name field with auto-lowercase
- [x] Region picker
- [x] Validation (3-63 chars, format)
- [x] XML body for non-us-east-1 regions
- [x] Duplicate name detection

### Delete Bucket
- [x] Normal delete (fails if not empty)
- [x] Force delete (empties then deletes)
- [x] Force delete confirmation with typing requirement
- [x] Progress display during force delete
- [x] Cancellable force delete

### Bucket Policy
- [x] GET bucket?policy
- [x] PUT bucket?policy
- [x] JSON editor with validation
- [x] Read-only mode respect

---

## 6. OBJECT OPERATIONS

### Object Listing & Navigation
- [x] Breadcrumb navigation (clickable path components)
- [x] Integrated search bar in breadcrumb row
- [x] Back/forward navigation (Cmd+[, Cmd+])
- [x] Navigation history with undo/redo
- [x] Parent directory (..) row
- [x] Double-click to navigate folders
- [x] Arrow key navigation (left=parent, right=enter folder)
- [x] Pagination with Previous/Next buttons
- [x] Session restore (path components)

### Object Table
- [x] Sortable columns: Name, Kind, Size, Date Modified, Actions
- [x] Customizable column visibility via @SceneStorage
- [x] Multi-select (Cmd/Shift click)
- [x] Alternating row styles
- [x] Per-row action buttons (download, preview, delete for files; open, info, delete for folders)

### Search & Filter
- [x] Inline search in current folder
- [x] Case-insensitive substring matching
- [x] Extension search (prefix "." for suffix match)
- [x] Auto-loads all pages if results are truncated
- [x] "No matches" empty state

### Object Context Menus — Single File
- [x] Download
- [x] Quick Look (preview)
- [x] Copy / Copy Key / Copy S3 URI / Copy as AWS JSON
- [x] Metadata (info sheet)
- [x] Rename
- [x] Move... (dialog or browse picker)
- [x] Move to > (submenu with parent and child folders)
- [x] Duplicate
- [x] Delete

### Object Context Menus — Single Folder
- [x] Open (navigate)
- [x] Folder Info (metadata)
- [x] Open in New Window
- [x] Download as ZIP
- [x] Copy / Copy Key / Copy S3 URI / Copy as AWS JSON
- [x] Rename
- [x] Move... (dialog or browse picker)
- [x] Move to > (submenu)
- [x] Duplicate
- [x] Paste Here (if clipboard populated)
- [x] Delete Folder

### Object Context Menus — Multi-Selection
- [x] Copy N Items / Copy N Paths / Copy N S3 URIs / Copy as AWS JSON
- [x] Move N Items... (dialog or browse picker)
- [x] Mixed Move to > (handles both files and folders)
- [x] Delete N Items

### Empty Folder Context Menu
- [x] Create Folder
- [x] Upload File
- [x] Upload Folder
- [x] Paste (when clipboard populated)

### Table Background Context Menu (right-click on non-row area)
- [x] Create Folder
- [x] Upload File
- [x] Paste
- [ ] **MISSING: "Upload Folder"** in table background context menu — The empty state context menu has it (line 465), but the table `.contextMenu(forSelectionType:)` when `ids.isEmpty` (line 710-724) only has Create Folder, Upload File, and Paste. Upload Folder is missing from the table background right-click.

---

## 7. COPY/PASTE SYSTEM

- [x] S3Clipboard model (source bucket, keys, prefixes)
- [x] Cmd+C to copy selected items
- [x] Cmd+V to paste into current folder
- [x] Paste into specific folder via context menu
- [x] Cross-bucket paste
- [x] Collision detection with user confirmation
- [x] Server-side copy operations

---

## 8. MOVE/RENAME/DUPLICATE

### Move
- [x] Within bucket via dialog
- [x] Within bucket via browse picker (S3FolderPickerView)
- [x] Quick buttons for parent and child folders
- [x] Cross-bucket move with bucket picker
- [x] Batch move (multiple objects)
- [x] Folder move (recursive)

### Rename
- [x] File rename (server-side copy + delete)
- [x] Folder rename (copy-all-then-delete-all)
- [x] Input validation (non-empty, no "/", no duplicates)

### Duplicate
- [x] Auto-generated names ("copy", "copy 2", etc.)
- [x] File and folder duplication
- [x] Server-side copy

---

## 9. METADATA VIEWS

### Object Metadata
- [x] File icon, name, bucket
- [x] General section: Key, Size, Type, Modified, ETag, S3 URI
- [x] Custom metadata (x-amz-meta-* headers)
- [x] Copy buttons with visual feedback

### Folder Metadata
- [x] Folder icon, name, bucket
- [x] Object count, total size
- [x] Path, parent path, S3 URI
- [x] Async scanning with progress

---

## 10. KEYBOARD SHORTCUTS

- [x] Cmd+[ / Cmd+] — Back/Forward
- [x] Left/Right arrow — Parent/Enter folder
- [x] Space — Quick Look preview
- [x] Cmd+C — Copy selected
- [x] Cmd+V — Paste
- [x] Cmd+Delete — Delete selected
- [ ] **MISSING: Cmd+F — Search focus** — S3BrowserApp has Cmd+F to focus the search bar. LocalCloudBrowser has a searchFocusTrigger but no keyboard shortcut wired to it for S3.
- [ ] **MISSING: Cmd+A — Select All** — S3BrowserApp has this via pasteboard commands. LocalCloudBrowser may rely on native Table behavior but doesn't explicitly wire it.

---

## 11. SETTINGS & PREFERENCES

- [x] Restore last session toggle
- [x] Double-click action picker (preview/metadata/download)
- [x] Auto-refresh interval picker
- [x] Quick Look size limit stepper
- [x] Preview cache toggle, size limit, clear button
- [x] Read-only mode toggle
- [x] AppPreferences with UserDefaults persistence

---

## 12. WINDOW MANAGEMENT

- [x] Multi-window support (S3BrowserWindow)
- [x] "Open in New Window" from bucket and folder context menus
- [x] S3BrowserTarget for window routing

---

## 13. DELETE OPERATIONS

### Single Object Delete
- [x] Delete button in row
- [x] Context menu delete
- [x] Confirmation dialog

### Batch Delete
- [x] Multi-select delete
- [x] Max 10 concurrent
- [x] Progress tracking
- [x] Confirmation dialog

### Folder Delete
- [x] Two-phase confirmation (optional scan first)
- [x] Recursive object enumeration (capped 10k)
- [x] Batch concurrent delete
- [x] Progress indication

---

## 14. DRAG & DROP

- [x] Inbound drop — files from Finder to upload
- [x] Inbound drop — folders from Finder
- [x] Drop target overlay visual indicator
- [ ] **MISSING: Outbound drag** — S3BrowserApp supports dragging files FROM the table TO Finder as NSFilePromiseProvider (downloads on drop). LocalCloudBrowser has no drag-out/file-promise support.

---

## 15. AUTO-REFRESH

- [x] AutoRefreshManager with configurable intervals
- [x] AutoRefreshIndicatorView with countdown
- [x] Manual mode (click to refresh)
- [x] Pauses during loading
- [x] Success/failure reporting

---

## 16. ERROR HANDLING

- [x] ServiceError XML/JSON parsing
- [x] Friendly message mapping for common AWS errors
- [x] CloudClientError with HTTP, network, read-only errors
- [x] S3ConfigHintView for LocalStack missing s3Domain
- [x] ConnectionLostBanner
- [x] Region redirect detection (PermanentRedirect)
- [ ] **MISSING: RetryBannerView** — (see Section 1)
- [ ] **MISSING: Credential expiration banner** — (see Section 1)

---

## 17. QUIT PREVENTION

- [ ] **MISSING: Quit prevention during active transfers** — S3BrowserApp's AppDelegate intercepts `applicationShouldTerminate` and prompts "Uploads in Progress — Cancel Transfers & Quit / Don't Quit". LocalCloudBrowser has no quit guard.

---

## SUMMARY OF GAPS

### High Priority (UX gaps users will notice)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| 1 | **No download progress for single files** | User has no feedback during large file downloads | Medium |
| 2 | **No Quick Look download progress overlay** | Preview feels frozen for large files | Low-Medium |
| 3 | **No outbound drag to Finder** | Can't drag files to desktop/Finder | Medium-High |
| 4 | **No retry banner UI** | User can't see/cancel retry attempts | Low |
| 5 | **No quit prevention during transfers** | Can accidentally quit and lose uploads | Low |
| 6 | **Missing "Upload Folder" in table background context menu** | Inconsistent with empty state context menu | Trivial |

### Medium Priority (Feature parity gaps)

| # | Gap | Impact | Effort |
|---|-----|--------|--------|
| 7 | **No credential expiration banner** | User must figure out expired creds from error messages | Low |
| 8 | **No Cmd+F for search focus** | Power users expect it | Trivial |
| 9 | **Multipart threshold mismatch (20MB vs 5MB)** | Medium files (5-20MB) use inefficient single PUT via S3Service path | Trivial |
| 10 | **Inconsistent URLSession usage** | Some S3 ops use URLSession.shared instead of configured session | Low |

### Lower Priority (Advanced features neither app fully has)

| # | Gap | Notes |
|---|-----|-------|
| 11 | Versioning (GetBucketVersioning, PutBucketVersioning) | Neither app |
| 12 | Object tagging | Neither app |
| 13 | Presigned URLs | Neither app |
| 14 | CORS/ACLs/Lifecycle management | Neither app |
| 15 | STS credential refresh | Neither app |
| 16 | Server-side encryption config | Neither app |
| 17 | Chunked concurrent downloads | Neither app |
| 18 | Resumable downloads | Neither app |
| 19 | Bandwidth throttling | Neither app |
| 20 | Listing/metadata TTL cache | Neither app |
