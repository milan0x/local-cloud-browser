# LocalStack Navigator — Implementation Plan

## Phase 1: Shell + Sidebar + Router (Scaffold)
- [x] Create Package.swift (macOS 14+, Swift 6.0)
- [x] App entry point with AppState
- [x] Route enum with all service cases
- [x] NavigationSplitView shell (ContentView + SidebarView)
- [x] Module protocol definition
- [x] Stub module views (S3, SQS, SNS, Secrets Manager)
- [x] SafetyGuard endpoint validation
- [x] ReadOnlyInterceptor
- [x] LocalStackClient (async HTTP)
- [x] ConnectionSettings model
- [x] Project documentation (CLAUDE.md, DESIGN.md, PLAN.md)
- [x] Verify build succeeds

## Phase 2: S3 Module
- [x] List buckets view
- [x] Create/delete bucket
- [x] Browse objects within a bucket
- [x] Upload/download objects
- [x] Object metadata viewer
- [x] Bucket policy editor
- [x] Fix S3 routing: use virtual-hosted-style (`s3.localhost.localstack.cloud`) for LocalStack v4+
- [x] Stable layout: bucket list uses inline header instead of toolbar to prevent shifts on selection
- [x] Bucket list pane capped at maxWidth 360 to prevent HSplitView rebalancing
- [x] Create bucket dialog shows region as disabled/grayed-out text
- [x] "+" button always visible (disabled in read-only mode instead of hidden)
- [x] All mutating actions (upload, delete, save policy) show as disabled/grayed instead of hidden in read-only mode
- [x] Drag-and-drop file upload from Finder into object browser (all view modes)
- [x] Visual drop-target feedback (dashed accent border + tint overlay)
- [x] List view: row selection via `Table(selection:)` binding
- [x] List view: double-click navigates folders / opens file metadata
- [x] List view: right-click context menu (Download, Metadata, Delete)
- [x] Pagination support for object listing (next/previous page, status bar)
- [x] Fix metadata sheet: use `.sheet(item:)` instead of `.sheet(isPresented:)` for reliable object binding
- [x] Read-only mode defaults to OFF — writes allowed on launch
- [x] ETag copy-to-clipboard button in metadata view (strips quotes, checkmark feedback)
- [x] Create folder (zero-byte `/`-suffixed keys) via toolbar button + sheet
- [x] Filter folder marker objects from object listing
- [x] Move objects between folders (`S3Service.moveObject` + context menu "Move..." sheet)
- [x] Back/forward navigation with history stack + toolbar buttons
- [x] Parent directory `..` row pinned at top when inside subfolders
- [x] Default sort order: date descending (newest first)
- [x] Folder picker (Browse...): revamped to mirror browser Table layout with files greyed out, clickable destination bar
- [x] Search & filter: reusable `SearchBarView` component, current-folder filter with extension matching, fixed-width bar (no layout shift)
- [x] Bucket list header rearranged: + button (white, before refresh menu), trash always visible (disabled until selection), pane widened to 260pt
- [x] Delete dialogs: native macOS `.alert()` for all deletes (objects, folders, buckets), multi-delete lists items on separate lines
- [x] Right-click context menus on empty areas: "Create Folder" + "Upload File" in empty object browser, "Create Bucket" in empty bucket list
- [x] Auto-refresh menu: `.menuStyle(.borderlessButton)` + `.fixedSize()` for compact icon rendering
- [x] S3 global region indicator: "Global" badge (dimmed) replaces region name when viewing S3, tooltip explains S3 buckets are not region-specific
- [x] Bucket list "Global" caption next to header title
- [x] Toolbar "Icons and Text" mode: action buttons use `Label` for proper display, search bar moved to breadcrumb bar
- [x] Toolbar refactored: shared `S3ToolbarState` (ObservableObject bridge) + `S3Toolbar` (reusable `ToolbarContent`), owned by parent view (S3ModuleView / S3BrowserWindow), buttons disabled when no bucket selected. Removed `ToolbarDisplayModeSaver` (KVO hack) and duplicate placeholder toolbar.
- [ ] Toolbar display mode persistence: **skipped** — SwiftUI's `toolbar(id:)` does not persist display mode reliably. KVO on `NSToolbar.displayMode` via NSViewRepresentable also failed (observer never attaches — SwiftUI manages toolbar lifecycle opaquely). May require NSWindowController or full AppKit toolbar ownership to solve. Low priority.
- [x] Sidebar title removed (empty `.navigationTitle("")`)
- [x] Default window size: 1100x700 via `.defaultSize()` on main WindowGroup
- [x] Sidebar column width: explicit `navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)`
- [x] Multi-select delete: `Set<RowItem.ID>` selection, `S3Service.deleteObjects()`, context menus adapt to show "Delete N Items", native `.alert()` lists item names
- [x] Human-readable file sizes: `S3Object.formattedSize` via `ByteCountFormatter` (.file count style), used in browser table, metadata views, folder picker
- [x] Copy Key / S3 URI / AWS JSON: right-click "Copy Key", "Copy S3 URI", "Copy as AWS JSON" for files and folders; "Copy Name" + "Copy S3 URI" for buckets; multi-select copies as newline-separated paths or AWS JSON
- [x] Quick Look preview: native macOS QLPreviewPanel for files (Spacebar, right-click "Quick Look", eye action button). Size limit configurable 1–50 MB (default 10 MB) via stepper in Settings, override alert for files up to 300 MB hard cap. Downloads streamed to disk via URLSession. Temp files in dedicated subfolder, cleaned on app launch + preview close.
- [x] Duplicate: right-click "Duplicate" for single files and folders, server-side copy via `x-amz-copy-source` header, Finder naming convention (`name copy.ext` → `name copy 2.ext`), collision check against loaded objects
- [x] Server-side copy upgrade: all move/copy operations (`moveObject`, `copyObject`, `moveObjectToBucket`, etc.) upgraded from GET+PUT to native `x-amz-copy-source` — no data downloaded/re-uploaded. General-purpose `serverSideCopy()` method in S3Service.
- [x] Rename: right-click "Rename" for single files (after Metadata) and folders (after Copy as AWS JSON). Rename sheet with validation (not empty, not same, no `/`). Files: server-side copy + delete. Folders: copy ALL then delete ALL (safe on failure). Disabled in read-only mode.
- [x] Download folder as ZIP: right-click "Download as ZIP" on folders. Downloads all objects preserving directory structure, zips with `/usr/bin/ditto`, NSSavePanel for save location. Progress indicator in status bar ("Downloading folder... 12/47"). Empty folder alert. Zero-byte folder markers filtered out. Temp cleanup after save/cancel.
- [x] "Date Added" column renamed to "Date Modified" — more accurate for S3's `LastModified` semantics
- [x] Delete button safety: bucket delete disabled when objects are selected (prevents accidental bucket deletion), tooltip explains "Click on the bucket you want to delete — objects are currently selected". Toolbar delete button red when enabled. `PaneClickDetector` (NSViewRepresentable + NSEvent monitor) on bucket list clears browser object selection on any click.

## Phase 3: SQS Module
- [ ] List queues view
- [ ] Create/delete queue
- [ ] Send message
- [ ] Receive/peek messages
- [ ] Queue attributes viewer
- [ ] Dead letter queue configuration

## Phase 4: SNS Module
- [ ] List topics view
- [ ] Create/delete topic
- [ ] Publish message
- [ ] Manage subscriptions
- [ ] Subscription filter policies

## Phase 5: Secrets Manager Module
- [ ] List secrets view
- [ ] Create/update secret
- [ ] View secret value (with reveal toggle)
- [ ] Delete secret
- [ ] Version history

## Phase 6: Settings & Polish
- [x] Settings UI (endpoint, region, auto-refresh interval, folder delete details toggle)
- [x] Persist settings to UserDefaults
- [x] Auto-refresh: reusable `AutoRefreshManager` on `AppState`, internal Task-based timer, `refreshTrigger` pattern
- [x] Auto-refresh indicator in S3 breadcrumb bar (countdown only)
- [x] Auto-refresh menu (single toolbar button: Refresh Now + interval picker)
- [x] Bucket list auto-refreshes alongside object browser
- [ ] Connection health check (ping LocalStack)
- [ ] Error handling improvements
- [ ] Keyboard shortcuts
- [ ] Menu bar integration
