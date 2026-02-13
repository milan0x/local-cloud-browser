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
- [x] ConnectionSettings model (later removed — replaced by ConnectionProfile)
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
- [x] Search & filter: reusable `SearchBarView` component, current-folder filter with extension matching, fixed-width bar (no layout shift). Search clears selection to prevent accidental deletion of hidden (filtered-out) items.
- [x] Cross-page folder search: when search is active and folder has multiple pages, fetches all pages via `listAllFolderContents()` and filters the full set client-side. Pagination controls hidden during search. Status bar shows "X of Y items" across all pages. Clearing search returns to paginated view.
- [x] Status bar selection count: shows "(N selected)" next to item count when 2+ items selected (excludes `..` parent row). Applied to both S3 object browser and SQS message browser.
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
- [x] Column customization: `TableColumnCustomization<RowItem>` with `@SceneStorage("S3ObjectColumns")` — right-click any column header for Finder-style checkmark menu to show/hide columns (Name, Kind, Size, Date Modified, Actions). All columns visible by default. Preferences persist across app launches.
- [x] Delete button safety: bucket delete disabled when objects are selected (prevents accidental bucket deletion), tooltip explains "Click on the bucket you want to delete — objects are currently selected". Toolbar delete button red when enabled. `PaneClickDetector` (NSViewRepresentable + NSEvent monitor) on bucket list clears browser object selection on any click.
- [x] Intra-app copy/paste: clipboard-based copy/paste using server-side copy (`x-amz-copy-source`). Right-click → "Copy" on files, folders, or multi-select. "Paste" on empty area, "Paste Here" on folders. Works across buckets and windows (clipboard stored on `AppState`). `S3Clipboard` model, `S3Service.copyFolder()` for recursive copy. Keyboard shortcuts: Cmd+C (copy), Cmd+V (paste), Cmd+Backspace (delete selected). Uses `FocusedValues` + `CommandGroup(replacing: .pasteboard)` with text field detection to fall through to standard text behavior in search bar, rename sheets, etc.
- [x] Collision detection — comprehensive safety system to prevent silent S3 PUT overwrites:
  - **Rename:** inline validation in rename sheet — checks new name against existing files/folders, disables "Rename" button with red warning text
  - **Create folder:** inline validation in create folder sheet — checks name against existing folders and files, disables "Create" button with red warning text
  - **Create bucket:** inline validation in create bucket sheet — checks name against existing buckets, disables "Create" button with red warning text
  - **Duplicate:** algorithmic avoidance via `duplicateName()` — always generates unique "name copy N.ext" names
  - **Move:** async `checkCollisions()` lists destination folder before `performMove()` — shows native `.alert()` with "Stop" / "Replace" if same-named items exist. Covers same-bucket move, cross-bucket move (`requestMoveToBucket()`), browse picker, "Move to" submenus, move sheet
  - **Paste:** async `checkCollisions()` lists destination before `performPaste()` — same alert. Covers empty-area "Paste" and folder "Paste Here"
  - Alert explains S3 merge behavior: matching items replaced, other existing items untouched, new items added
- [x] Force delete non-empty buckets: catches `BucketNotEmpty` error when deleting, shows confirmation alert requiring user to type "delete". `S3Service.emptyBucket()` lists all objects (paginated) and deletes them, `forceDeleteBucket()` empties then deletes. Progress overlay with `ProgressView("Deleting...")` while running. Multi-bucket support.

## Phase 3: SQS Module
- [x] List queues view
- [x] Create/delete queue (standard and FIFO)
- [x] Send message (with optional delay, message group ID, deduplication ID for FIFO). Sheet 480×460pt — Options and FIFO settings at the top, message body TextEditor (monospaced, 180pt min height) at the bottom for natural top-to-bottom flow.
- [x] Receive/peek messages: uses `ReceiveMessage` with `VisibilityTimeout=0` so messages stay visible to real consumers (peek mode). Accumulates messages across refreshes with deduplication by `messageId` — new receives merge with existing list, replacing duplicates with the latest version.
- [x] Queue attributes viewer (visibility timeout, delay, max size, retention, wait time, ARN, FIFO settings)
- [x] Dead letter queue configuration (redrive policy editor)
- [x] SQS JSON protocol: uses `X-Amz-Target: AmazonSQS.<Action>` headers with JSON payloads (not Query/XML like older AWS SDKs). `LocalStackClient.sqsRequest(action:payload:)` handles this.
- [x] Read-only mode: checked at SQS action level, not HTTP method level. A whitelist of safe actions (ListQueues, GetQueueUrl, GetQueueAttributes, ReceiveMessage, ListQueueTags, ListDeadLetterSourceQueues) bypasses the HTTP read-only check via `skipReadOnlyCheck`, since SQS uses POST for everything including reads.
- [x] `ServiceError.parse(from:)` extended to handle SQS JSON error format (`__type` + `message` fields) alongside the existing S3 XML error format (`<Code>` + `<Message>`).
- [x] Message browser — rich Table view with 8 columns providing at-a-glance information for debugging and monitoring:
  - **Message ID:** Truncated display (`first 8...last 4` chars, e.g. `a1b2c3d4...7890`) to show recognizable bookends of the UUID without wasting horizontal space. Full ID available on hover tooltip and via right-click "Copy Message ID". Sortable column.
  - **Type:** Colored capsule badge detecting body content format — "JSON" (blue) if body starts with `{` or `[`, "XML" (orange) if body starts with `<`, "Text" (gray) otherwise. Helps quickly identify message payload format without reading the body. Sortable column.
  - **Body:** First 200 characters, split on newlines, each line trimmed, joined with single space — eliminates indentation whitespace from pretty-printed JSON. Full body (up to 500 chars) shown on hover tooltip. Double-click opens detail view with full body and JSON pretty-printing (original key order preserved).
  - **Size:** Body size in bytes/KB (`body.utf8.count`). Useful for spotting unexpectedly large or empty messages at a glance. Sortable column.
  - **Sent:** Relative timestamp (e.g. "5 min ago") from the `SentTimestamp` system attribute. Shows when the message was originally published to the queue. Sortable column — **default sort is newest-first** (sent timestamp descending) so the most recent messages appear at the top, which is the natural expectation when monitoring a queue for new activity.
  - **Receives:** `ApproximateReceiveCount` — how many times a consumer has received this message. High counts indicate processing failures or visibility timeout issues. Useful for identifying "poison pill" messages that keep failing. Sortable column with monospaced digits for alignment.
  - **Group ID:** `MessageGroupId` attribute — only populated for FIFO queues, shows which message group the message belongs to (FIFO queues guarantee ordering within a group). Shows "—" for standard queues. Helps debug FIFO partitioning.
  - **First Received:** `ApproximateFirstReceiveTimestamp` — when a consumer first picked up this message. Comparing this to "Sent" reveals queue latency (how long the message sat before being processed). Shows "—" if the message has never been received by a consumer.
- [x] Message browser sort: messages are deduplicated via a dictionary (`[messageId: SQSMessage]`) after each receive poll, then sorted by `sortOrder` (array of `KeyPathComparator`). Default sort is `sentTimestampMillis` descending (newest first). Users can click any sortable column header to re-sort, and click again to reverse direction. Sort is stable across refreshes.
- [x] Message context menu: View Details, Copy Message ID, Copy Message Body, Copy as AWS CLI, Delete (single or multi-select). "Copy as AWS CLI" generates `aws sqs send-message` with the real message body (shell-escaped), queue URL, endpoint, and region. Hidden for multi-select (only makes sense for one message). Delete shows native `.alert()` confirmation.
- [x] Toolbar: shared `SQSToolbarState` (ObservableObject bridge) with pending action pattern — Send Message, Receive, Delete Selected, Show Attributes. Each module defines its own toolbar independently.
- [x] Queue list double-click to open attributes: double-clicking a queue in the queue list opens the queue attributes sheet directly, consistent with S3's double-click pattern (file → metadata). Also added "View Attributes" as the first item in the queue right-click context menu for discoverability. Uses `.sheet(item: $queueToShowAttributes)` with `SQSQueueAttributesView`. Auto-refresh pauses while the attributes sheet is open. Double-click detected via `QueueDoubleClickDetector` — an `NSViewRepresentable` placed as `.background` on the queue `List` that installs an `NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown)` monitor with **bounds checking**: converts `event.locationInWindow` to its own coordinate space and only fires when `self.bounds.contains(pointInSelf)` and `event.clickCount == 2`. This scopes double-click detection to the queue list pane only, preventing false triggers when double-clicking messages in the adjacent browser pane. Same pattern as `PaneClickDetector` in S3BucketListView.
- [x] Queue attributes view UI polish: sheet 580pt, `.body` monospaced fonts for ARN with `lineLimit(nil)` wrapping. Configuration labels shortened ("Visibility Timeout" not "Visibility Timeout (s)"), unit text ("seconds", "bytes") spelled out next to each text field in `.fixedSize()` HStacks. Validation messages include human-readable equivalents (e.g. "1 min–14 days"). Queue name displayed as the first row in "Queue Info" section (above ARN) with click-to-copy via `CopyableValue`.
- [x] Message detail view UI polish: sheet 580pt, all monospaced values use `.body` size with wrapping. Shows Queue (copyable), Message ID, Type, Sent, Size, Group ID (FIFO), First Received, Receive Count, MD5, Body (JSON pretty-print), and raw Attributes. Fields ordered by importance — Queue and Message ID at top, MD5 hash at bottom.
- [x] Click-to-copy with blur overlay (`CopyableValue` component, `Navigation/CopyableValue.swift`): `Button(.plain)` wrapping value text. Hover blurs text (3pt gaussian) and shows "Copy to Clipboard" overlay with `doc.on.doc` icon. Click copies to `NSPasteboard`, shows green "Copied to Clipboard" with checkmark for 1.2s, then unblurs. Overlay uses `.allowsHitTesting(false)`. Applied to Queue Attributes (ARN, Created, Last Modified) and Message Detail (Message ID, MD5, Sent, First Received, Receive Count, Group ID, all raw attributes). Excluded from Type and Size (too small).
- [x] Body copy button (`CopyButton` component): standalone icon button in the Body section header. Fixed-size `ZStack` with opacity-swapped icons (`doc.on.doc` ↔ `checkmark`) in 16×16 frame to prevent layout shifts. Green checkmark feedback for 1.5s.

### SQS Quick Send Favorites
- [x] `SavedSQSFavorite` data model (`Modules/SQS/SavedSQSFavorite.swift`): Codable/Identifiable/Hashable struct with `id` (UUID), `name` (String, max 25 chars), `queueUrl` (String, per-queue scoping), `messageBody`, optional `delaySeconds`/`messageGroupId`/`messageDeduplicationId`, `createdAt`.
- [x] `SQSFavoriteStore` persistence (`Modules/SQS/SQSFavoriteStore.swift`): `@MainActor` ObservableObject, `@Published var favorites: [SavedSQSFavorite]`, JSON encode/decode to UserDefaults key `"SQSFavorites"`. CRUD: `add()`, `update()`, `delete(id:)`. `favorites(for queueUrl:)` returns sorted subset. Created as `@StateObject` on `SQSModuleView`, passed to children as `@ObservedObject`.
- [x] Send message sheet save toggle (`SQSSendMessageView.swift`): "Save as Quick Message" toggle in its own form section (below Message Body, at the bottom of the form). When toggled ON, a "Name" `TextField` appears below the toggle — smart prefill (for JSON bodies, extracts a descriptive value from common keys like `type`/`event`/`action`/`name`; fallback uses queue short name), max 25 char limit. Bottom bar has three buttons: Cancel (left), Save (center, only visible when toggle is ON + name is non-empty), Send (right). Save button saves the favorite without sending and dismisses. Send button sends without saving (unless toggle is ON, in which case it also saves). Edit mode: when `editingFavorite` is non-nil, toggle starts ON, name pre-filled, "Update" replaces "Save". Delay field hidden for FIFO queues (FIFO doesn't support per-message delay). Delay field is numeric-only — `onChange` strips non-digit characters as typed. Send errors use modal `.serviceErrorAlert()` instead of inline red text. Message type (JSON/XML/Text) is auto-detected from body content at display time — no type selector needed. **Body type + validity badges:** section header shows live capsule badges — type pill (JSON blue, XML orange, Text gray) appears when body is non-empty, validity pill (Valid green checkmark, Invalid red xmark) shown for JSON/XML only. JSON validated via `JSONSerialization.jsonObject(with:)`, XML via `XMLParser.parse()`. Body is trimmed before detection so leading whitespace doesn't cause misdetection. **Smart substitutions disabled:** `.disableSmartSubstitutions()` on the TextEditor + `NSText.didBeginEditingNotification` observer on the window disables smart quotes, smart dashes, and auto-replacement for the message body and all TextFields (FIFO group ID, dedup ID, etc.) in the sheet.
- [x] Favorites bar (`SQSMessageBrowserView.swift`): horizontal `ScrollView` of `FavoriteChip` views below the status bar, 36pt height, `.bar` background. Only visible when queue has favorites.
- [x] `FavoriteChip` (private struct): compact rounded rect with star icon + name label (max 25 chars keeps chips small). **Two-click send:** first click highlights chip (accent border + tint, label changes to "Click to Send"), second click sends the message + shows mini spinner. Clicking elsewhere / another chip / selecting a message row clears armed state. `@State private var armedFavoriteId: UUID?` on browser view. Disabled (grayed out) in read-only mode. **Context menu:** Send, Edit (opens send sheet with fields populated), Delete. **Layout-stable animation:** icon (star ↔ spinner) and text (name ↔ "Click to Send") both use `ZStack` + opacity toggle pattern — chip always takes the width of the wider text, no layout shifts on armed/sending state changes. Smooth `.easeInOut(duration: 0.15)` transitions keyed to `isArmed` and `isSending`. **Hover effect:** background darkens on mouse hover (`.onHover`). **Sent animation:** after successful send, chip briefly shows green checkmark + "Sent" text with green-tinted background for 0.8s before returning to normal (`sentFavoriteId` state).
- [x] Module wiring (`SQSModuleView.swift`): `@StateObject private var favoriteStore = SQSFavoriteStore()`, passed to `SQSMessageBrowserView` and through to `SQSSendMessageView`.

### SQS JSON Helper
- [x] JSON helper DSL: indentation-based syntax that compiles to JSON in real-time. `JSONHelperParser` (`Modules/SQS/JSONHelperParser.swift`) tokenizes lines by indent level, builds a tree of objects/arrays/values, serializes to pretty-printed JSON. Supports: quoted strings, numbers, booleans, null, nested objects (indent children), arrays (`- "item"`). Error messages include line numbers.
- [x] Body type + validity badges: section header shows live capsule badges — type pill (JSON blue, XML orange, Text gray) when body is non-empty, validity pill (Valid green checkmark, Invalid red xmark) for JSON/XML. "Read-Only" badge when helper is active (body editor is disabled/dimmed). Caption text below editor explains: "Message body is generated by the JSON Helper below. Edit the helper to update."
- [x] `CodeTextEditor` (`Modules/SQS/CodeTextEditor.swift`): `NSViewRepresentable` wrapping `NSTextView` in `NSScrollView`. Used for both the message body and JSON helper input areas. Replaces SwiftUI `TextEditor` to provide code-editor-like behavior:
  - **No-wrap horizontal scrolling:** `isHorizontallyResizable = true`, `textContainer.widthTracksTextView = false`, infinite container size. Long lines scroll horizontally instead of wrapping — preserves formatting for JSON/XML content.
  - **Auto-hiding scrollbars:** `autohidesScrollers = true` on NSScrollView. Vertical and horizontal scrollbars only appear when content exceeds the visible area — no phantom scrollbars on short content.
  - **`isEditable` parameter:** Controls editability from SwiftUI. When transitioning from disabled to enabled (e.g., closing JSON Helper), auto-focuses the text view via `makeFirstResponder`.
  - **Transparent background:** `drawsBackground = false` on NSTextView — background provided by SwiftUI `.background()` layer. Allows `.opacity()` modifier to dim only text, not background, when editor is read-only.
  - **Auto-indentation on Enter:** `AutoIndentTextView` (private `NSTextView` subclass) overrides `insertNewline(_:)` — walks backward from cursor to find current line start, counts leading whitespace, inserts `\n` + same whitespace. Preserves indentation level for natural nested structure editing.
  - **Tab-to-spaces:** `insertTab(_:)` inserts 4 spaces instead of a tab character, preventing focus change.
  - **Smart substitutions disabled internally:** `isAutomaticQuoteSubstitutionEnabled`, `isAutomaticDashSubstitutionEnabled`, `isAutomaticTextReplacementEnabled` all set to `false` directly on the NSTextView — no need for the external `.disableSmartSubstitutions()` modifier.
  - **Binding sync:** Coordinator (`NSTextViewDelegate`) pushes `textView.string` to `$text` on `textDidChange`. `isUpdating` flag prevents re-entrant updates when SwiftUI pushes a new value down via `updateNSView`. Only updates `textView.string` when binding differs (prevents cursor jumps).
  - **Auto-focus on appear:** `makeNSView` schedules `window?.makeFirstResponder(textView)` via `DispatchQueue.main.async`. When the JSON Helper is opened, focus moves into the helper input automatically.
  - Monospaced font, undo support, vertical + horizontal scrolling.
- [x] Placeholder example on empty body: when JSON Helper is active and the message body is empty, shows `JSONHelperParser.defaultJSON` (the parsed JSON output of the default example) as placeholder text. Helper input also shows the default DSL example as placeholder. No auto-fill — user starts with a blank input and the placeholder disappears on typing.
- [x] "Example Data" button (left side of helper button row): always toggles a syntax reference popover (read-only, no text fields — avoids NSPopover keyboard issues). Popover shows: syntax legend (key types: string, number, boolean, null, nested object, array), compact example, and a "Fill Example Data" button that replaces helper text and dismisses the popover. Monospaced font, 300pt width.
- [x] **Bidirectional editing:** Reverse parser `JSONHelperParser.fromJSON()` converts JSON → helper DSL format. Uses a custom ordered JSON scanner (`JSONScanner`) that preserves key order (unlike `JSONSerialization`). When the JSON Helper is opened and the message body contains valid JSON, it's reverse-parsed into the helper input. Flow: edit helper → JSON updates in body; close helper → edit JSON directly → reopen helper → helper reflects changes.
- [x] **Double-click to close JSON Helper:** Optional feature gated by `AppPreferences.doubleClickHidesJsonHelperKey` (Settings > SQS). When enabled, double-clicking the dimmed message body area hides the JSON Helper and makes the body editable. Transparent `Color.clear` overlay with `.onTapGesture(count: 2)`. Disabled by default.
- [x] **Disable placeholders:** Optional feature gated by `AppPreferences.disableSQSPlaceholdersKey` (Settings > SQS). Hides placeholder text in both the message body editor (JSON preview when helper is active) and the JSON Helper editor (example DSL text). Disabled by default.
- [x] Default example trimmed to minimal: one child per nested structure (`address` → just `city`, `tags` → just one item) to keep it concise.

### SQS Message Browser Polish
- [x] Column customization: `TableColumnCustomization<SQSMessage>` with `@SceneStorage("SQSMessageColumns")` — right-click any column header for Finder-style checkmark menu to show/hide columns. Preferences persist across app launches. Each column has a `.customizationID()` for stable identification.
- [x] Default column visibility: Message ID, Body, Type, Sent, Size visible by default. Receives, Group ID, First Received hidden by default (`.defaultVisibility(.hidden)`) — available via right-click header menu.
- [x] Column order by importance: Message ID → Body → Type → Sent → Size → Receives → Group ID → First Received. Body moved to second position (right after Message ID) for content-first scanning.
- [x] Column widths tuned for compact defaults without max constraints (user can drag-resize freely): Message ID (min 100, ideal 115), Body (min 150, flexible), Type (min 42, ideal 48), Sent (min 60, ideal 75), Size (min 32, ideal 38), Receives (min 45, ideal 55), Group ID (min 70, ideal 90), First Received (min 80, ideal 110), Actions (min 80, ideal 100). No `max` on any column — start compact, user stretches as needed.
- [x] Type badge consistency: fixed 38pt `frame(width:)` with `.caption2` font and `.semibold` weight so JSON, XML, and Text badges are all the same capsule size regardless of label length.
- [x] Actions column: inline icon buttons matching S3 object browser pattern — View Details (eye), Copy Message Body (doc.on.doc), Delete (trash, red when enabled, gray when read-only). Uses `HStack(spacing: 8)` with `.buttonStyle(.borderless)` per button. Delete disabled in read-only mode.
- [x] Message detail view: Queue Name added as first field (copyable via `CopyableValue`). Fields reordered by importance: Queue → Message ID → Type → Sent → Size → Group ID → First Received → Receive Count → MD5 (hash moved to bottom as least-used). Body pretty-print uses a string-level JSON formatter (`prettyPrintJSON`) that indents without parsing into a dictionary — preserves original key order exactly as authored. `JSONSerialization` round-trip was removed because `NSDictionary` scrambles key order even without `.sortedKeys`.
- [x] Body preview whitespace fix: message browser Body column now splits on newlines, trims each line, then joins with a single space — eliminating visible indentation gaps from pretty-printed JSON bodies.
- [x] String-level JSON pretty-printer (`prettyPrintJSON`): walks JSON string character by character, tracking string boundaries and escape sequences, inserts newlines/indentation at structural characters (`{`, `}`, `[`, `]`, `,`). Replaces `JSONSerialization` round-trip which used `NSDictionary` (unordered) and scrambled key order even without `.sortedKeys`. Validates JSON first via `JSONSerialization.jsonObject` before formatting; falls back to raw body if invalid.
- [x] Queue context menu "Copy as AWS CLI": submenu with three items — Send Message, Receive Message, Get Attributes. Each generates a ready-to-paste `aws` CLI command with the queue URL, endpoint, and region from `appState`. FIFO queues include `--message-group-id` in the Send Message template.
- [x] CLI helpers on `SQSQueue` model: `sendMessageCLI()`, `receiveMessageCLI()`, `getAttributesCLI()` — all take `endpointUrl` and `region` parameters, return multi-line `aws sqs` commands with backslash continuations. `SQSMessage.toAWSCLI()` generates `aws sqs send-message` with the actual message body (single-quote shell escaping: `'` → `'\''`), queue URL, endpoint, region, and optional `--message-group-id` for FIFO.

### SQS Send Message Style Polish
- [x] Message body uses `CodeTextEditor`: replaced SwiftUI `TextEditor` with `CodeTextEditor(text:isEditable:)` — both message body and JSON helper input now share the same NSTextView-based editor with no-wrap horizontal scrolling, auto-hiding scrollbars, and consistent padding via `textContainerInset`.
- [x] Message body header fixed height: `.frame(height: 18, alignment: .leading)` on the HStack — prevents layout shift when body type badges (JSON/XML/Text, Valid/Invalid) conditionally appear as user types. Without this, badge appearance changed header height and pushed section content up/down.
- [x] Modal height increased from 580 to 650 (non-JSON-helper mode) so the "Save as Quick Message" section is visible without scrolling.
- [x] `DisableSmartSubstitutions` extended with optional `textContainerInset: NSSize?` parameter — sets `NSTextView.textContainerInset` during initial configuration. Default nil preserves existing behavior.
- [x] "Read-Only" badge restyled: orange text on light orange background (`Color.orange.opacity(0.25)`) for better visibility when JSON Helper is active. Previously gray/secondary which was too subtle.
- [x] Text input visual consistency: both message body and JSON helper input now have matching `textBackgroundColor` fill + `separatorColor` rounded border (6pt corners) so they read clearly as editable areas within the Form section card.
- [x] JSON helper input padding matched to message body: `CodeTextEditor.textContainerInset` increased from `NSSize(width: 4, height: 6)` to `NSSize(width: 6, height: 10)` so text offset matches between both editors. Placeholder padding adjusted accordingly.
- [x] Double-click to close JSON helper now focuses message body: `CodeTextEditor` detects `isEditable` transition (false → true) and auto-focuses via `makeFirstResponder`.

## Phase 4: SNS Module
- [ ] List topics view
- [ ] Create/delete topic
- [ ] Publish message
- [ ] Manage subscriptions
- [ ] Subscription filter policies
- [ ] Session restore: add `snsTopicArn: String?` to `LastSessionState`, `saveSNSTopic(_:)` to `LastSessionStore`, add field to `clearSubResources()`, snapshot capture in `SNSModuleView.init()`, `restoreTopicArn` param on topic list view, restore logic after loading topics (see S3/SQS pattern)

## Phase 5: Secrets Manager Module
- [ ] List secrets view
- [ ] Create/update secret
- [ ] View secret value (with reveal toggle)
- [ ] Delete secret
- [ ] Version history
- [ ] Session restore: add `secretName: String?` to `LastSessionState`, `saveSecretName(_:)` to `LastSessionStore`, add field to `clearSubResources()`, snapshot capture in `SecretsManagerModuleView.init()`, `restoreSecretName` param on secrets list view, restore logic after loading secrets (see S3/SQS pattern)

## Phase 6: Settings & Polish
- [x] Settings UI (endpoint, region, auto-refresh interval, folder delete details toggle)
- [x] Persist settings to UserDefaults
- [x] Sidebar-style settings: redesigned SettingsView with fixed sidebar (General, S3, SQS tabs) and detail pane. Uses HStack + List(.sidebar) instead of NavigationSplitView to avoid toolbar/collapse controls. General: session restore, health check interval, auto-refresh interval. S3: Quick Look preview size, folder delete details. SQS: placeholders, double-click JSON Helper.
- [x] Global auto-refresh: moved refresh interval from S3 settings to General — single interval applies to all modules. Toolbar `AutoRefreshMenuView` in each module reads/writes the same `appState.autoRefresh.interval`.
- [x] Auto-refresh: reusable `AutoRefreshManager` on `AppState`, internal Task-based timer, `refreshTrigger` pattern
- [x] Auto-refresh indicator in S3 breadcrumb bar (countdown only)
- [x] Auto-refresh indicator click target expansion: added `.padding(.horizontal, 4)` + `.padding(.vertical, 2)` + `.contentShape(Rectangle())` inside the button label so the entire padded area is clickable, not just the icon and text pixels
- [x] Auto-refresh menu (single toolbar button: Refresh Now + interval picker)
- [x] Bucket list auto-refreshes alongside object browser
- [x] Auto-refresh selection stability fix (deselection during mouse-hold):
  - **Problem:** Holding the mouse button on a Table/List item and waiting for the auto-refresh timer to tick would deselect the item. Quick click-and-release worked fine, but press-and-hold during any timer activity dropped the selection.
  - **Root cause:** `@EnvironmentObject var autoRefresh: AutoRefreshManager` on module views (S3ObjectBrowserView, S3BucketListView, SQSQueueListView, SQSMessageBrowserView) subscribed them to `objectWillChange` on the entire `AutoRefreshManager`. Because `countdownRemaining` is `@Published` and decrements every second, ALL module views had their `body` re-evaluated every single second. Each re-evaluation recomputed `sortedRowItems` (a computed property) producing new struct instances. This caused the underlying NSTableView to process potential data source updates, which disrupted any in-progress mouse gesture (click-hold, drag-select).
  - **Why `.onChange` wasn't enough:** Using `.onChange(of: autoRefresh.refreshTrigger)` only fires the handler at countdown zero, but `@EnvironmentObject` still triggers body re-evaluation on EVERY `@Published` change (including every-second countdown ticks). With `ObservableObject`, there is no per-property subscription — `objectWillChange` fires for all properties.
  - **Fix — three layers:**
    1. **`triggerPublisher` (PassthroughSubject):** Added to `AutoRefreshManager`. Fires only at countdown zero and manual `triggerNow()`. Module views subscribe via `.onReceive(appState.autoRefresh.triggerPublisher)` instead of `.onChange(of: autoRefresh.refreshTrigger)`.
    2. **Removed `@EnvironmentObject var autoRefresh` from module views:** Views access the manager through `appState.autoRefresh` (a `let` property — not `@Published`, so changes to the manager don't trigger `appState.objectWillChange`). `AutoRefreshIndicatorView` (countdown display) and `SettingsView` (interval picker) keep their direct observation — they legitimately need every-second updates.
    3. **Silent refresh mode:** Auto-refresh calls use `silent: true` which skips `isLoading`, `errorMessage`, `lastLoadTime`, `toolbarState.isLoading`, `reportSuccess()`/`reportFailure()` state changes. Data arrays are diffed before assignment (`objects != result.objects`). For SQS messages specifically, comparison is by message ID set (because `receiptHandle` changes on every receive, making full `Equatable` comparison always fail).
  - **Manual `Binding` for `AutoRefreshMenuView`:** Since `@EnvironmentObject` was removed, `$autoRefresh.interval` is no longer available. Replaced with `Binding(get: { appState.autoRefresh.interval }, set: { appState.autoRefresh.interval = $0 })`. Functionally identical.
  - **Known limitations of this fix:**
    - `PassthroughSubject` doesn't replay: if a view is being destroyed/recreated at the exact moment a trigger fires, it could theoretically miss one trigger. Next trigger catches up. Extremely unlikely (view lifecycle is synchronous and sub-millisecond, triggers are seconds apart).
    - Silent mode skips `isLoading = true`: no concurrency guard against overlapping silent refreshes. In practice, triggers are spaced by the interval (minimum 1s) and LocalStack responds in <100ms. Even if overlap occurred, worst case is a redundant harmless network call.
    - Silent mode skips `reportSuccess()`/`reportFailure()`: verified that `lastRefreshFailed` and `lastSuccessfulRefresh` are NOT read by any view — the health check handles connection status independently. No visible effect.
    - `fetchMessageCounts()` in SQSQueueListView still runs during silent refresh and writes to `@State messageCounts` dict. SwiftUI should detect `Dictionary<String, Int>` equality and skip re-render when counts haven't changed. If counts DID change, the re-render is correct behavior.
  - **Alternative approaches considered and rejected:**
    - **Mouse-down tracking (NSEvent monitor):** Would only delay the problem — queued refresh fires on mouse release, causing visual jump. Doesn't cover keyboard selection. Complex per-view NSEvent infrastructure.
    - **Migrating to `@Observable` (Observation framework):** Would provide per-property tracking natively. Rejected because it requires changing all `@EnvironmentObject` to `@Environment(Type.self)` (optional unwrapping), `@Bindable` for bindings in SettingsView, and is a larger refactor for the same result. The `PassthroughSubject` approach is more surgical.
    - **Caching `sortedRowItems` in `@State`:** Would decouple Table data from body re-evaluations. Rejected because it requires manual cache invalidation on every data/sort/filter change — error-prone and adds complexity.
- [x] Connection health check: polls `/_localstack/health` at a configurable interval (default 2 seconds, options: 1, 1.5, 2, 3, 4, 5 seconds — Settings > General "Health check interval") with a 5-second manual Task-race timeout (ephemeral URLSession per check, invalidated after). `AppState.healthCheckInterval` persisted to UserDefaults via `AppPreferences.healthCheckIntervalKey`; `didSet` restarts the health check loop immediately on change. Two-state `ConnectionStatus` enum: `.connected` (200 response), `.disconnected` (timeout/error). Parses full health JSON into `HealthInfo` on `AppState`: version, edition, and all services. "available" and "running" are healthy; anything else is unhealthy. `ConnectionError` enum captures failure reason: `.timeout`, `.httpError(Int)`, `.networkError(String)`. Consecutive failure tracking: first failure shows `questionmark.circle.fill` with palette rendering (orange question mark, silver-gray fill — signals uncertain state), second consecutive failure sets `connectionError` and shows orange `exclamationmark.triangle.fill` — clickable popover shows error reason + endpoint. Connected resets counter immediately. Four visual states: connected+healthy (green `checkmark.circle.fill`, service dashboard popover), connected+issues (orange `exclamationmark.triangle.fill`, service dashboard), disconnected first failure (gray `questionmark.circle.fill`, no popover), disconnected 2+ failures (orange `exclamationmark.triangle.fill`, error details popover). Profile switch resets `consecutiveFailures` and `connectionError`.
- [x] "Connection lost" bubble notification: small floating bubble above sidebar bottom bar when connection fails (2+ consecutive failures). Shows orange warning icon + "Connection lost" text + close button. Persists until dismissed or connection recovers. Dismissed state resets when connection recovers, so a fresh failure cycle shows the bubble again.
- [x] Session restore — two-layer design:
  - **Intra-session memory (always on, not configurable):** Switching between services (S3 → SQS → S3) always restores the last selected bucket/queue/path. SwiftUI destroys module views on route switch, so intra-session restore relies on `LastSessionStore` — saves happen unconditionally via `onChange`, and module `init()` unconditionally reloads from the store. Works regardless of the cross-launch flag because `clearSubResources()` only runs once on launch; after that, `onChange` repopulates sub-resource fields as the user makes selections.
  - **Cross-launch restore ("Open where I left off", configurable):** Gated by `LastSessionStore.isEnabled` (toggle in Settings > General, default `true`). When enabled, restores both the route (in `LocalStackNavigatorApp.init`) and per-module sub-resources (bucket/queue/path). When disabled, `clearSubResources()` wipes saved sub-resource fields on launch so modules start fresh — no route restore, no bucket/queue/path restore. Module `init()` always loads from `LastSessionStore` unconditionally; when the flag is off, the data is simply empty. Each module view captures a snapshot in its `init()` via `@State`, passes restore params to children (`restoreBucketName`, `restorePath`, `restoreQueueName`). Children use `@State hasRestoredSession/hasRestoredPath` flags to consume once per view lifecycle. Collision safety: `S3ObjectBrowserView` checks `restoreBucketName == bucket.name` before restoring path, preventing stale paths from bleeding into wrong buckets. Deleted resources: `first(where:)` returns nil → no selection, user sees the list.
  - **Infrastructure:** `LastSessionState` Codable model stored as JSON in UserDefaults. `LastSessionStore` enum with per-field save methods (`saveRoute`, `saveS3Bucket`, `saveS3Path`, `saveSQSQueue`) and `clearSubResources()` (wipes bucket/path/queue fields). Route saved via `ContentView.onChange(of: selectedRoute)`. S3 bucket/path and SQS queue saved via `onChange` in module views.
- [x] Connection UX improvements:
  - **Instant reconnection indicator:** `AppState.notifyConnectionAlive()` called by `LocalStackClient` on any successful HTTP response — immediately flips the health indicator to green without waiting for the next health check cycle. Fixes the lag where module data loaded instantly but the bottom-left indicator stayed gray/orange.
  - **Configurable health check interval:** Picker in Settings > General with options 1, 1.5, 2, 3, 4, 5 seconds (default 2). Persisted to UserDefaults. Changing the interval restarts the health check loop immediately via `didSet`.
  - **Bidirectional reconnection detection:** Health check and module refreshes cross-trigger each other. (1) Module → indicator: `LocalStackClient` calls `notifyConnectionAlive()` on any successful response. (2) Indicator → modules: when health check detects `.disconnected → .connected` transition, calls `autoRefresh.triggerNow()` to fire all module refreshes immediately and reset the countdown. Whichever system detects reconnection first triggers the other — no waiting for the next poll/countdown cycle.
  - **Stale data banner:** When a module list (buckets/queues) has cached data but a refresh fails, an orange "Connection lost — showing cached data" banner overlays the bottom of the list. Previously, the error was invisible because the error-state branch only rendered when the list was empty.
  - **Docker troubleshooting hint:** Network errors (`LocalStackClientError.networkError`) now append "Check that your Docker container is running and the LocalStack endpoint is reachable." to the error description.
  - **First-failure icon:** Changed from empty gray `circle` to `questionmark.circle.fill` with palette rendering (orange question mark, silver-gray fill) to signal uncertain connection state.
  - **Click target expansion:** Health status and connection error buttons in the sidebar bottom bar now have `.padding(4)` + `.contentShape(Rectangle())` for a larger hit region.
  - **"Connection lost — retrying..." hint:** Shown below the loading spinner in bucket/queue list views when `connectionError` is set (2+ consecutive failures). Only appears after confirmed disconnection, not on the first transient blip.
- [ ] Error handling improvements
- [x] Keyboard shortcuts: Cmd+C/V for S3 copy/paste, Cmd+Backspace for delete (objects only, shows confirmation dialog)
- [x] Region picker: `AWSRegion` static data model (39 regions). `AWSRegionPicker` convenience wrapper using native SwiftUI `Picker` for form contexts (S3 create bucket dialog, connection profile editor). Only valid AWS region codes selectable. Create bucket dialog restructured from plain VStack to `Form` with `.formStyle(.grouped)` matching the connection profile editor — info label in its own `Section`, `Divider` + button bar below, 380pt width.
- [x] Clickable toolbar region badge: native `Menu` (default style, NOT `.borderlessButton` — borderless style has broken hit testing where only the icon/text is clickable, not the full toolbar area). Label uses explicit `HStack { Image + Text }` (not `Label` — toolbar context may hide label text). S3 shows a disabled dimmed `Menu` with "Global" text. Non-S3 modules (SQS, SNS, Secrets Manager) show region code with dropdown. Both use `Menu` so AppKit renders them as their own toolbar group, separate from `.primaryAction` icons. Selecting a region updates `appState.region` immediately. macOS menus support type-to-jump natively.
- [x] Region persistence via profile: toolbar region picker updates the active connection profile's region (single source of truth). Removed `UserDefaults`-based region persistence (`regionKey`, `didSet`, startup override hack). On launch, `applyProfile()` sets region from the active profile. On toolbar change, both `appState.region` and the active profile are updated and saved.
- [x] Keychain credential storage: `accessKeyId` and `secretAccessKey` moved from plaintext UserDefaults to macOS Keychain (Security framework). `KeychainHelper` utility wraps `SecItemAdd`/`SecItemUpdate`/`SecItemCopyMatching`/`SecItemDelete` with service name `"LocalStackNavigator"`, keyed by profile UUID. `ConnectionProfile.CodingKeys` excludes credential fields from JSON serialization — UserDefaults only stores non-sensitive data (id, name, endpoint, region). `ConnectionProfileStore` hydrates credentials from Keychain on load, saves to Keychain on add/update, deletes from Keychain on profile delete. One-time migration (`CredentialsMigratedToKeychain` flag): reads old plaintext credentials from UserDefaults via `LegacyProfile` struct, moves to Keychain, re-saves profiles without credentials.
- [x] Smart Keychain: skip Keychain for default LocalStack credentials (`test`/`test`) — no password prompts on launch for typical users. `KeychainHelper.isDefaultCredentials()` gates all save/load paths. `saveCredentials()` removes any existing Keychain entry when credentials match defaults (cleans up entries from previous versions). `ConnectionProfile.init(from:)` decoder falls back to `KeychainHelper.defaultAccessKeyId`/`defaultSecretAccessKey` instead of empty strings. Default profile creation skips `saveCredentials()` entirely. `KeychainHelper.save()` uses update-or-add pattern (`SecItemUpdate` then `SecItemAdd`) instead of delete-then-add to minimize Keychain operations. Migration flag set on default profile creation to prevent unnecessary legacy migration on second launch. Keychain only activated when users add custom (non-default) credentials.
- [x] Default connection profile named "default connection" — concise lowercase label. Connection name font in sidebar bottom bar set to `.callout` for readability. Connection status dot changed from red/green to gray/green (gray = not connected, green = connected) to avoid alarming "error" appearance.
- [x] Profile picker UI: replaced `Menu` (ellipsis.circle + dropdown chevron artifact) with a single edit button (ellipsis.circle, `.primary` style) per profile row. No delete button in the picker — delete is only available inside the editor to prevent accidental deletion.
- [x] Connection editor delete: "Delete Connection" button (red text, trash icon, `role: .destructive`) in its own form section at the bottom of the editor. Native `.alert()` confirmation showing profile name, endpoint, and region. On delete, auto-switches to the next available profile.
- [x] Default profile protection: `ConnectionProfileStore` tracks `defaultProfileId` (persisted to UserDefaults). The auto-created default profile cannot be deleted — editor shows an info note ("This is a default profile and cannot be deleted.") instead of the delete button. User-created profiles show the delete button when more than one profile exists (cannot delete the last remaining profile).
- [x] Editor sheet fix — stale @State on first open: replaced `.sheet(isPresented:)` + separate `editingProfile` state with `.sheet(item:)` using an `EditorSheet` wrapper struct (fresh `UUID` each presentation). This forces SwiftUI to create a completely new `ConnectionProfileEditorView` with fresh `@State` every time the sheet opens, fixing the bug where the name field appeared empty on first edit and only populated after opening a different profile first. Root cause: `.sheet(isPresented:)` can reuse the view identity across presentations, causing `@State(initialValue:)` to retain values from the initial body evaluation when `editingProfile` was still nil.
- [x] Editor text field auto-select fix: added `@FocusState` (starts nil) to the name `TextField` so no field is auto-focused when the editor opens — prevents macOS from selecting/highlighting the entire name text on appear.
- [x] Editor frame height: 440pt when editing (both delete button and info note cases), 380pt when adding a new profile.
- [x] Deleted unused `ConnectionSettings.swift` — dead code, fully replaced by `ConnectionProfile`
- [x] Connection profile picker hit target: expanded clickable area to cover both connection name text and chevron icon (`.contentShape(Rectangle())` + padding). Previously only the text registered clicks.
- [ ] Menu bar integration

## Known macOS SwiftUI Limitations

These are platform-level issues that cannot be worked around cleanly. Documented here so future attempts don't repeat the same investigation.

### NSPopover cannot accept keyboard input (text fields inside popovers)

**Root cause:** `NSPopover`'s internal window (`_NSPopoverWindow`) returns `false` from `canBecomeKey`. This means the popover window can never become the key window, so all keyboard events are routed to the main window instead (e.g. the sidebar's type-to-select in `NavigationSplitView`). This is a macOS AppKit limitation, not a SwiftUI bug — it affects both SwiftUI `.popover()` and manually created `NSPopover` instances.

**Symptom:** A `TextField` inside a `.popover` appears but cannot be typed into. Keystrokes go to the sidebar (changing selection), cause the popover to close and reopen, or are silently dropped.

**Approaches tried and why they failed:**
1. **SwiftUI `@FocusState` + `.focused()`** — Focus state has no effect because the popover window cannot become key. The focus request is silently ignored.
2. **`NSViewRepresentable` wrapping `NSTextField` with `window.makeKey()`** (`PopoverTextField`) — `makeKey()` is a no-op when `canBecomeKey` returns `false`. The NSTextField gets created but never receives keyboard events.
3. **Custom `NSPopover` with `.semitransient` behavior** (`KeyboardPopover` modifier) — `.semitransient` prevents auto-dismiss on outside clicks but does NOT change `canBecomeKey`. The popover still can't receive keyboard events.
4. **`popoverDidShow` delegate + `popoverWindow.makeKey()`** — Same issue: `makeKey()` is silently ignored because `canBecomeKey` is `false`.
5. **`NSEvent.addLocalMonitorForEvents(.keyDown)` key interception** — Captures key events at app level and forwards them to the text field via `interpretKeyEvents`. The text field updates, but this triggers a SwiftUI state change → view re-evaluation → `NSHostingController.rootView` update → the popover content is rebuilt, causing visual flicker (popover closes and reopens) on every keystroke.

**Current solution:** Use native `Menu` (NSMenu) for the toolbar region picker — macOS menus support type-to-jump natively. For form contexts (sheets/dialogs), use native SwiftUI `Picker` which renders as a standard macOS popup button. Neither requires a text field inside a popover.

**If a searchable popover is needed in the future:** The only reliable approaches would be: (a) a custom `NSPanel` subclass positioned near the anchor view (NSPanel can become key), or (b) a `.sheet` presentation which is a proper modal window.

**Removed files:** `SearchableDropdown.swift` (custom popover dropdown with filter), `KeyboardPopover.swift` (NSPopover wrapper), `PopoverTextField` struct (NSTextField wrapper with event monitor). All replaced by native `Menu` / `Picker`.

### @EnvironmentObject re-renders on every @Published change (no per-property tracking)

**Root cause:** `@EnvironmentObject` (and `@ObservedObject`) subscribe to `objectWillChange` on the entire `ObservableObject`. When ANY `@Published` property changes, ALL views that observe that object have their `body` re-evaluated — even if the view only reads one specific property. There is no per-property subscription with the `ObservableObject`/`@Published` pattern.

**Symptom in this project:** `AutoRefreshManager` has `@Published countdownRemaining` which decrements every second. Module views (S3ObjectBrowserView, S3BucketListView, etc.) that had `@EnvironmentObject var autoRefresh` were re-rendered every second, even though they only needed `refreshTrigger` (which changes every N seconds at countdown zero). The every-second re-renders caused NSTableView to process potential data source updates, disrupting in-progress mouse gestures (click-and-hold deselection).

**Solution:** Removed `@EnvironmentObject var autoRefresh` from module views. Added a `PassthroughSubject<Void, Never>` (`triggerPublisher`) to `AutoRefreshManager` that fires only at countdown zero. Module views subscribe via `.onReceive(appState.autoRefresh.triggerPublisher)`. Access to other manager methods goes through `appState.autoRefresh` (a `let` property on AppState — not `@Published`, so it doesn't trigger `appState.objectWillChange`).

**Alternative:** The `@Observable` macro (Observation framework, macOS 14+) provides per-property tracking natively. Migrating `AutoRefreshManager` to `@Observable` would solve this without a manual publisher. However, it requires changing all injection sites (`@EnvironmentObject` → `@Environment(Type.self)`), adding `@Bindable` for bindings, and is a larger refactor. The `PassthroughSubject` approach is more surgical and achieves the same result.

**General rule:** If an `ObservableObject` has frequently-changing properties (timers, counters, progress) alongside infrequently-changing ones (triggers, configuration), consider either: (a) splitting into separate objects, (b) using a targeted `PassthroughSubject`/`NotificationCenter` for the infrequent events, or (c) migrating to `@Observable`.

### Smart quotes/dashes in TextEditor and TextField

**Root cause:** macOS enables automatic quote substitution (`"` → `""`) and dash substitution (`--` → `—`) by default on `NSTextView`, which SwiftUI's `TextEditor` wraps. `TextField` uses a shared window field editor (`NSTextView`) that also has these enabled. This mangles JSON/XML input — `{"key":"value"}` becomes `{"key":"value"}`.

**Symptom:** User types a straight quote in TextEditor or TextField, it initially appears correct, then transforms into a curly/smart quote on the next run loop cycle. This breaks structured data (JSON, XML, bucket policies).

**Why one-shot configuration fails:** Setting `isAutomaticQuoteSubstitutionEnabled = false` via `viewDidMoveToWindow` works initially but SwiftUI can reconfigure the underlying `NSTextView` at any time, re-enabling smart quotes. The setting gets silently overridden.

**Solution (`Navigation/DisableSmartSubstitutions.swift`):** `.disableSmartSubstitutions()` View modifier places an invisible `NSViewRepresentable` background that: (1) walks up the view hierarchy to find and configure the `NSTextView` for TextEditor on initial load, and (2) observes `NSText.didBeginEditingNotification` scoped to the window to reconfigure on every editing session start — this catches SwiftUI reconfiguration, field editor reuse across TextFields, and focus changes. Observer is cleaned up in `removeFromSuperview()`. Applied to: SQS send message body TextEditor, S3 bucket policy TextEditor.

**Scope:** Only TextEditors used for structured data input need this. Single-line TextFields for names, numbers, paths, and IDs don't need it — quotes are virtually never typed in those fields, and the window field editor fix from the nearest `.disableSmartSubstitutions()` covers them anyway.

### Toolbar button hit target mismatch

SwiftUI toolbar buttons have a smaller click area than AppKit's `NSToolbarItem` hover/press circle. The circle highlight is rendered by AppKit (~32pt), but the SwiftUI `Button` only registers clicks on the `Label`/`Image` content (~16-20pt). Clicking the edge of the highlighted circle does nothing.

**Solution (`Navigation/ToolbarHitTarget.swift`):** `.toolbarHitTarget()` View modifier — applies `.frame(width: 36, height: 36)` + `.contentShape(Rectangle())` to expand the SwiftUI hit area to cover the full AppKit circle. Apply to the `Label` inside every toolbar `Button`:
```swift
Button { ... } label: {
    Label("Action", systemImage: "icon.name")
        .toolbarHitTarget()
}
```
**All new modules must apply `.toolbarHitTarget()` to their toolbar button labels.**

**Side effect — toolbar group capsules:** Adding `.toolbarHitTarget()` makes AppKit's group capsule (shared rounded background for same-placement items) more prominent. Non-control views (plain `HStack`) in a `ToolbarItem` get absorbed into adjacent groups. Fix: wrap in a `Menu` (even disabled/empty) — default style, NOT `.borderlessButton` (which has broken hit testing). AppKit treats `Menu` as a distinct control with its own separate group capsule. This is why the S3 "Global" badge uses a disabled `Menu`.

**Toolbar Menu hit testing:** NEVER use `.menuStyle(.borderlessButton)` for toolbar menus — it makes the `NSPopUpButton` hit area match only the visible content (icon/text), not the full toolbar background area. Clicks on the pill edges pass through to the title bar. Use the default `Menu` style instead — it renders as a standard macOS dropdown with full hit area. Use `HStack { Image + Text }` for the label (not `Label` — toolbar context may hide label text in icon-only mode).

### Toolbar display mode persistence

`toolbar(id:)` only persists item customization, not display mode. KVO on `NSToolbar.displayMode` via NSViewRepresentable fails because SwiftUI manages the toolbar lifecycle opaquely — the observer never reliably attaches. Would require NSWindowController or full AppKit toolbar ownership. Low priority.

## Future Ideas

### JSON Helper UX improvements (SQS Send Message)
- **Preserve helper text across sheet opens:** Currently `jsonHelperText` is `@State` — it resets when the sheet is dismissed and reopened. Consider persisting helper text (per queue or globally) so users can iterate on a message structure across multiple send sessions without retyping.
- **Syntax highlighting:** Color-code keys, string values, numbers, booleans, and array markers (`-`) in the `CodeTextEditor` to make the DSL easier to scan. Could use `NSTextStorage` attributed string updates in `textDidChange`.
- **Auto-closing quotes:** Typing `"` inserts `""` and places the cursor between them, similar to code editors. Would reduce keystrokes for string-heavy messages.
- **Line numbers gutter:** Add a line number column to `CodeTextEditor` to help users match parse errors ("Line 5: invalid value") to their input.
- **Undo across sessions:** The `CodeTextEditor` supports undo within a session (`allowsUndo = true`), but undo history is lost when the sheet closes. If helper text is persisted, consider whether undo history should also persist.
- **Template library:** Beyond the single default example, let users save their own DSL templates (like quick messages but for the helper format). Useful for teams that frequently send messages with the same structure but different values.
