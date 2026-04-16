# S3 Feature Port Plan: S3BrowserApp → LocalCloudBrowser

## Reference Codebase
- **Source (up-to-date):** `/Users/milan/dev/s3 browser app/` (internally "Bucketeer", 196 commits)
- **Target (this project):** `/Users/milan/dev/LocalCloudBrowser/`

## Dependency Graph
```
Phase 1 (Core Models)
  └→ Phase 2 (RetryExecutor + RequestSigningContext)
       └→ Phase 3 (StreamingUploader)
            ├→ Phase 4 (TransferManager + TransferItem)
            │    ├→ Phase 5 (Transfer UI: Popover, Pill, Banner, Toolbar Button)
            │    │    └→ Phase 13 (ContentView & App-Level Integration)
            │    └→ Phase 11 (S3ObjectBrowserView Integration)
            └→ Phase 10 (S3Service Upload Refactor)
                 └→ Phase 11

Phase 6  (AutoRefreshManager)           — independent
Phase 7  (Preview Cache)                — independent, needs Phase 1
Phase 8  (LastSessionStore)             — independent
Phase 9  (AppPreferences + Settings)    — after Phase 6, 7, 8
Phase 12 (Keyboard Navigation)          — independent
Phase 14 (sortedRows Performance)       — independent
Phase 15 (Empty States + Swipe)         — independent
Phase 16 (S3BrowserWindow)              — independent
Phase 17 (Unit Tests)                   — runs alongside each phase
Phase 18 (Final Verification)           — after all phases
```

---

## Phase 1: Core Models & Types

### What to create

**File: `LocalCloudBrowser/Networking/TransferTypes.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3BrowserCore/TransferTypes.swift`

```
TransferDirection: enum, Sendable
  - .upload, .download

TransferState: enum, Sendable, Equatable
  - .queued, .active, .completed, .failed(String), .cancelled
  - computed: isFinished → Bool

TransferProgress: enum (namespace)
  - static fractionCompleted(bytesTransferred: Int64, totalBytes: Int64) → Double
```

**File: `LocalCloudBrowser/Networking/RetryPolicy.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3BrowserCore/RetryPolicy.swift`

```
RetryDecision: enum, Sendable, Equatable
  - .retry(after: TimeInterval)
  - .doNotRetry(reason: String)

RetryPolicy: struct, Sendable
  - maxRetries: Int = 3
  - baseDelay: TimeInterval = 1.0
  - maxDelay: TimeInterval = 30.0
  - jitterFactor: Double = 0.25
  - delay(for attempt: Int) → TimeInterval  (exponential backoff with jitter)
  - static shouldRetry(statusCode:, isNetworkError:, attempt:, policy:) → RetryDecision
  - retryableStatusCodes: Set<Int> = [500, 502, 503, 504]
  - static defaultPolicy, noRetry

RetryAttempt: struct, Sendable, Identifiable
  - id: UUID, attemptNumber: Int, maxAttempts: Int, error: String, nextRetryDate: Date?
```

**File: `LocalCloudBrowser/Networking/MultipartUploadPlan.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3BrowserCore/MultipartUploadPlan.swift`

```
UploadPartRange: struct, Sendable
  - partNumber: Int, offset: Int64, length: Int

CompletedPart: struct, Sendable
  - partNumber: Int, etag: String

MultipartUploadPlan: struct, Sendable
  - parts: [UploadPartRange], partSize: Int, fileSize: Int64, isMultipart: Bool
  - Constants: minimumPartSize=5MB, maximumPartCount=10_000, defaultPartSize=8MB
  - static plan(fileSize:, preferredPartSize:) → MultipartUploadPlan
  - static completeMultipartXML(parts:) → Data

MultipartInitiateParser: XMLParserDelegate
  - parse(data:) throws → String (uploadId)
```

**File: `LocalCloudBrowser/Modules/S3/PreviewCache.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3BrowserCore/PreviewCache.swift`

```
PreviewCacheEntry: struct, Codable, Equatable, Sendable
  - endpoint, bucket, key, etag, diskFilename: String
  - fileSize: Int64, lastAccessed: Date (mutable)

PreviewCacheIndex: final class, Sendable
  - CacheKey: struct (endpoint, bucket, key)
  - static diskFilename(for:) → String (SHA-256 hash, preserves extension)
  - static loadIndex(from:), saveIndex(_:to:)
  - static lookup(_:in:directory:), upsert(_:in:)
  - static totalSize(of:directory:), evict(entries:directory:maxBytes:)
  - static pruneOrphans(entries:directory:), clearAll(directory:)
```

**File: `LocalCloudBrowser/Networking/ContentMD5.swift`** (NEW or verify existing)
Check if already exists. If not, port from: `S3BrowserApp/Sources/S3BrowserCore/ContentMD5.swift`

```
ContentMD5: enum
  - static md5(_ data: Data) → Data  (CryptoKit Insecure.MD5)
  - static contentMD5Header(_ data: Data) → String  (base64-encoded)
```

### Tests to write (Phase 17, but plan now)
- TransferTypesTests: 8 tests (direction, state equality, isFinished, fractionCompleted edge cases)
- RetryPolicyTests: 11 tests (backoff calc, max delay cap, jitter bounds, status codes, network errors)
- MultipartUploadPlanTests: 7 tests (small file, threshold, part calc, offsets, large file scaling, XML generation, parser)
- PreviewCacheTests: 16 tests (codable, filename generation, index persistence, lookup, upsert, eviction, orphans, totalSize, clearAll)
- ContentMD5Tests: 4 tests (empty data, known hash, base64 format, consistency)

### Checkpoint
- [ ] All 5 files compile with `swift build` / `xcodebuild`
- [ ] No dependency on UI or AppState
- [ ] All types are Sendable where specified

---

## Phase 2: RetryExecutor & RequestSigningContext

### What to create

**File: `LocalCloudBrowser/Networking/RetryExecutor.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/Networking/RetryExecutor.swift`

```swift
func withRetry<T: Sendable>(
    policy: RetryPolicy = .defaultPolicy,
    operation: String = "",
    onRetry: (@Sendable (RetryAttempt) -> Void)? = nil,
    body: @Sendable () async throws -> T
) async throws -> T
```
- Loop up to maxRetries
- Catch errors → check isRetryable (network errors or 5xx)
- Extract statusCode from CloudClientError.httpError
- Call RetryPolicy.shouldRetry() for decision
- On .retry: call onRetry callback, Task.sleep with backoff delay
- On .doNotRetry: rethrow
- Check Task.isCancelled before and after sleep

**File: `LocalCloudBrowser/Networking/RequestSigningContext.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/Networking/StreamingUploader.swift` (lines 21-107)

```
RequestSigningContext: struct, Sendable
  - endpoint, s3BaseURL, region: String
  - accessKeyId, secretAccessKey, sessionToken: String
  - needsSigning, isReadOnly, usesVirtualHostedStyle: Bool
  - signedS3Request(method:path:queryParams:body:contentType:payloadHash:extraHeaders:) → URLRequest
  - private resolveURL(for path:) → URL
```

**Modify: `LocalCloudBrowser/Networking/CloudClient.swift`**
Add method:
```swift
func makeSigningContext() -> RequestSigningContext
```
Snapshots current appState credentials into a Sendable struct for background use.

**Modify: `LocalCloudBrowser/Networking/CloudClient.swift`**
Add computed property to CloudClientError:
```swift
var isRetryable: Bool  // network errors + 5xx
```

### Checkpoint
- [ ] `withRetry` compiles and can wrap any async throws function
- [ ] `makeSigningContext()` returns correct snapshot from AppState
- [ ] CloudClientError.isRetryable returns true for 500/502/503/504 and network errors

---

## Phase 3: StreamingUploader

### What to create

**File: `LocalCloudBrowser/Networking/StreamingUploader.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/Networking/StreamingUploader.swift`

```
ByteAccumulator: private final class, Sendable
  - NSLock-based thread-safe Int64 counter
  - add(_ bytes: Int64), var value: Int64

StreamingUploader: final class, Sendable
  - session: URLSession
  
  uploadSingleFile(
    fileURL: URL,
    signingContext: RequestSigningContext,
    bucket: String, key: String,
    contentType: String,
    progress: @Sendable (Int64, Int64) -> Void
  ) async throws
  — Uses UNSIGNED-PAYLOAD (avoids loading file for signing)
  — Sets Content-Length from file attributes
  — URLSession.upload(for:fromFile:)

  uploadMultipart(
    fileURL: URL,
    signingContext: RequestSigningContext,
    bucket: String, key: String,
    contentType: String,
    plan: MultipartUploadPlan,
    progress: @Sendable (Int64, Int64) -> Void
  ) async throws
  — Step 1: POST ?uploads → parse uploadId via MultipartInitiateParser
  — Step 2: withThrowingTaskGroup, max 4 concurrent parts
    - FileHandle.seek to offset, read partSize bytes
    - Content-MD5 per part
    - Sign with part-specific path (?partNumber=N&uploadId=X)
    - Collect CompletedPart (partNumber, etag)
    - ByteAccumulator tracks cumulative bytes
  — Step 3: POST with completeMultipartXML body
  — defer: abortMultipartUpload on failure
```

### Key differences from current LocalCloudBrowser
- Current: Multipart logic is inline in S3Service.putObjectMultipart()
- New: Separate Sendable class that can run off MainActor
- Current: Signs on main thread via CloudClient
- New: Signs via RequestSigningContext snapshot (background-safe)
- Current: No ByteAccumulator (progress per-part only)
- New: Thread-safe cumulative progress across concurrent parts

### Checkpoint
- [ ] StreamingUploader compiles as Sendable
- [ ] Can upload a file via single PUT
- [ ] Can upload a file via multipart with progress
- [ ] defer block properly aborts on failure

---

## Phase 4: TransferManager & TransferItem

### What to create

**File: `LocalCloudBrowser/Networking/TransferManager.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/Networking/TransferManager.swift`

```
TransferItem: @MainActor ObservableObject, Identifiable
  - id: UUID
  - fileName: String
  - direction: TransferDirection
  - @Published state: TransferState
  - @Published bytesTransferred: Int64
  - @Published totalBytes: Int64
  - task: Task<Void, Never>?
  - startedAt: Date
  - localURL: URL?, s3Key: String?, s3Bucket: String?, contentType: String?
  - computed: fractionCompleted: Double
  - updateBytes(bytesTransferred:totalBytes:)

UploadRequest: private struct
  - fileName, localURL, s3Key, s3Bucket, contentType, totalBytes

TransferManager: @MainActor ObservableObject
  @Published items: [TransferItem]
  pendingQueue: [UploadRequest]
  queueTask: Task<Void, Never>?
  onFileUploaded: ((String, String, Int64) -> Void)?  // bucket, key, size
  @Published lastBatchResult: BatchResult?
  isProcessingQueue: Bool

  — Computed properties:
    activeCount, queuedCount, completedCount, failedCount
    totalBatchCount, pendingFileCount, pendingBytes
    hasActiveTransfers, activeDirection, totalFileCount
    overallProgress: Double (0.0-1.0)
    summaryText: String ("Uploading 3/10 — 67%")
    activeBucketNames, activeBucketCount, completedBucketCount, totalBucketCount

  — Per-bucket queries:
    queuePositionForBucket(_:) → (pendingFiles, filesAhead, bucketsAhead, isActive)
    totalFileCountForBucket(_:), completedCountForBucket(_:)
    failedCountForBucket(_:), progressForBucket(_:)

  — Queue operations:
    enqueueUploads(_:uploadHandler:)  — registers files, starts processor
    processQueue()  — AsyncStream-based 6-slot concurrency
    add(fileName:direction:totalBytes:state:) → TransferItem
    updateProgress(id:bytesTransferred:totalBytes:)
    complete(id:), fail(id:message:), cancel(id:)
    cancelAll(), cancelForBucket(_:)
    clearCompleted(), clearAll()
```

### Why 6-slot concurrency (from S3BrowserApp design notes)
- Single-threaded queue was too slow for many small files
- Unlimited concurrency caused SigV4 signing races and connection exhaustion
- 6 slots balances throughput vs resource use
- AsyncStream with manual slot release provides fine-grained control

### Checkpoint
- [ ] TransferManager can enqueue 20 files and process 6 at a time
- [ ] Per-bucket progress queries return correct values
- [ ] Cancel/fail/complete state transitions work
- [ ] onFileUploaded callback fires per-file

---

## Phase 5: Transfer UI Components

### What to create (all in `LocalCloudBrowser/Navigation/`)

**File: `TransferPopoverView.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/Navigation/TransferPopoverView.swift`

```
TransferPopoverView: View
  @EnvironmentObject transferManager: TransferManager
  — Frame: width 340, dynamic height (56pt/item + 48 header/footer, min 140, max 360)
  — Empty state: transfer icon + "No transfers" text
  — Transfer list: active + queued + last 10 completed
  — Hidden count: "and N more queued" in tertiary color
  — Footer HStack: "Cancel All" button (if active) | Spacer | "Clear" button (if finished)
  — Footer background: .bar

TransferRowView: View
  @ObservedObject item: TransferItem
  — HStack(spacing: 8):
    - Direction icon 16pt: arrow.up (blue) / arrow.down (green)
    - VStack: fileName (.callout, .truncationMode(.middle)) + state sub-view
      - .queued: "Waiting..." tertiary caption2
      - .active: linear ProgressView + "X / Y" bytes
      - .completed: "Completed" secondary caption2
      - .failed: "Failed: X" red caption2
      - .cancelled: "Cancelled" secondary caption2
    - Spacer(minLength: 0)
    - Cancel button (if active/queued) or state icon (checkmark/warning/dash)
```

**File: `TransferToolbarButton.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/Navigation/TransferToolbarButton.swift`

```
TransferToolbarButton: View
  @EnvironmentObject transferManager: TransferManager
  @State showPopover = false
  — Button toggles showPopover
  — Icon: arrow.up.arrow.down.circle
  — Badge overlay (topTrailing): blue capsule with totalFileCount
    - Font: system(size: 9, weight: .bold), white on blue
    - Offset: x: 6, y: -6
    - Only shows if hasActiveTransfers
  — Popover: TransferPopoverView, arrowEdge: .bottom
  — Opacity: 0.5 if empty, 1.0 otherwise
```

**Embedded in S3ObjectBrowserView: `TransferPillView`** (NEW, private struct)
Port from: `S3BrowserApp` lines 2704-2817

```
Position: .overlay(alignment: .bottom) on the table content area
  — Padding: .bottom 12

TransferPillView properties:
  @ObservedObject transferManager, bucketName, showCompletionPause,
  completionPauseCounts, showTransferCancelled, showUploadComplete,
  showTransferFailed, failedTransferCounts, onCancel, onDismissFailure

Three pill types:
  1. progressPill: HStack(spacing: 6)
     - Direction icon (arrow.up/down.circle.fill, blue/green, .caption)
     - Progress text: "Uploading — X%" or "Uploading — X/Y · X%" (.monospacedDigit, .caption, .fontWeight(.medium))
     - Cancel: xmark.circle.fill (.secondary, .caption)
     - Background: Capsule().fill(.ultraThinMaterial)
     - Shadow: .black.opacity(0.15), radius 4, y 2
     - Progress ring: Capsule overlay .trim(from: 0, to: progress) .stroke(accentColor, lineWidth: 2)
     - Animation: .easeInOut(duration: 0.4)
     - Padding: .horizontal 12, .vertical 6

  2. failurePill: same shape, orange warning icon, orange stroke border

  3. statusPill: same shape, simpler (icon + text only)
```

**Embedded in S3ObjectBrowserView: `UploadQueueBanner`** (NEW, private struct)
Port from: `S3BrowserApp` lines 2516-2569

```
Position: above the table, below breadcrumb bar (VStack ordering)

UploadQueueBanner properties:
  @ObservedObject transferManager, bucketName, onRefresh

Conditional: shows only if transferManager.hasActiveTransfersForBucket(bucketName)

Layout: HStack(spacing: 8)
  - Active: ProgressView(.controlSize(.small)) + "Uploading X of Y files — Z%"
  - Queued: clock icon + "Upload queued — X buckets, Y files ahead"
  - Starting: ProgressView + "Upload starting — X files"
  - Refresh button: arrow.clockwise (.callout, .secondary)
  - All text: .callout, .foregroundStyle(.secondary), .monospacedDigit

Background: .quaternary.opacity(0.5)
Padding: .horizontal 12, .vertical 6
```

**Embedded in S3ObjectBrowserView: `StatusBarTransferIndicator`** (NEW, private struct)
Port from: `S3BrowserApp` lines 2574-2617

```
Position: in the existing status bar HStack (right side, before pagination controls)

Layout: HStack(spacing: 6)
  - Bucket counter (if totalBuckets > 1): "X of Y" (.callout, .secondary)
  - Linear ProgressView (width: 120)
  - Percentage: "XX%" (.callout, .monospacedDigit, .secondary)
  - Info icon: info.circle (.callout, .secondary)
  — Button toggles popover with TransferDetailPopover
```

### Where these go in the existing view hierarchy
```
S3ObjectBrowserView body (current):
  VStack(spacing: 0) {
    BreadcrumbBar(...)
    // INSERT: UploadQueueBanner here
    if isLoading { ... }
    else { Table(...) }
    // INSERT: TransferPillView as .overlay(alignment: .bottom) on Table
    StatusBar {
      // INSERT: StatusBarTransferIndicator in right side
    }
  }
```

### Checkpoint
- [ ] TransferPopoverView shows active/queued/completed transfers
- [ ] TransferToolbarButton shows badge count
- [ ] TransferPillView animates progress at bottom of table
- [ ] UploadQueueBanner shows queue status above table
- [ ] StatusBarTransferIndicator shows linear progress in footer

---

## Phase 6: AutoRefreshManager

### What to create

**File: `LocalCloudBrowser/App/AutoRefreshManager.swift`** (NEW — replace existing if one exists)
Port from: `S3BrowserApp/Sources/S3Browser/App/AutoRefreshManager.swift`

```
AutoRefreshManager: @MainActor ObservableObject
  let triggerPublisher = PassthroughSubject<Void, Never>()
  @Published var interval: Int  (persisted to UserDefaults "autoRefreshInterval")
    — didSet: resetCountdown() if changed
  @Published private(set) countdownRemaining: Int = 0
  @Published private(set) lastSuccessfulRefresh: Date?
  @Published private(set) lastRefreshFailed: Bool = false
  @Published private(set) refreshTrigger: Int = 0
  @Published private(set) isAwaitingResponse: Bool = false

  computed: isActive (interval != 0), isManualMode (interval == -1)

  init(): loads from UserDefaults, defaults to 5s, starts timer
  
  Timer: private Task that sleeps 1s per tick
  tick(): guards active + not manual + not awaiting + countdown > 0, decrements, fires at 0
  fireRefresh(): sets isAwaitingResponse, increments refreshTrigger, publishes
  reportSuccess(): records timestamp, clears flags, resets countdown
  reportFailure(): records failure, clears awaiting, resets countdown
  triggerNow(): fires immediately, resets countdown
  resetCountdown(): sets countdown = interval
  resetState(): clears everything
```

**File: `LocalCloudBrowser/App/AutoRefreshIndicatorView.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/App/AutoRefreshIndicatorView.swift`

```
AutoRefreshIndicatorView: View
  @ObservedObject manager: AutoRefreshManager
  var onRefreshNow: (() -> Void)?

  Conditional: if manager.isActive
  Three states:
    1. Awaiting: mini ProgressView, accentColor
    2. Manual: arrow.clockwise button, accentColor
    3. Auto: HStack(spacing: 2) arrow.clockwise + "Xs" countdown (.monospacedDigit)
  All: .caption font, .horizontal 4 + .vertical 2 padding, .plain button style
```

### Where to wire
- **AppState:** Already has AutoRefreshManager — verify it matches this spec
- **S3ObjectBrowserView:** Listen to `autoRefresh.refreshTrigger` via `.onChange`, call `loadObjects(force: true, silent: true)`, then `reportSuccess/Failure`
- **ListHeaderBar:** Add AutoRefreshIndicatorView next to refresh button
- **SettingsView:** Add "Refresh interval" picker (Off/1s/3s/5s/10s/30s/60s)

### Checkpoint
- [ ] Timer counts down and triggers refresh
- [ ] Countdown pauses while awaiting response
- [ ] Manual mode shows click-to-refresh button
- [ ] Settings picker persists interval

---

## Phase 7: Preview Cache System

### What to modify

**File: `LocalCloudBrowser/Modules/S3/S3QuickLookManager.swift`** (MODIFY)
Reference: `S3BrowserApp/Sources/S3Browser/S3/S3QuickLookManager.swift`

Add:
- Private `cacheIndex: [PreviewCacheEntry]` loaded on init
- On previewObject():
  1. If cache enabled: HEAD request → get ETag
  2. Build CacheKey(endpoint, bucket, key)
  3. lookup() in index → if hit AND ETag matches → serve from disk, update lastAccessed
  4. If miss: download → move to cache dir → upsert index → evict if over limit → save index
  5. If cache disabled: download to temp, cleanup on dismiss
- On init: if cache enabled, loadIndex + pruneOrphans + evict over limit
- clearCache(): PreviewCacheIndex.clearAll() + reload index

### What to add to Settings (Phase 9)
- Toggle "Cache previewed files" (AppPreferences.previewCacheEnabledKey)
- Stepper "Cache size limit: X MB" (50-1000, step 50)
- "Clear Cache" button + "Currently using X MB" display

### Checkpoint
- [ ] First preview downloads and caches
- [ ] Second preview of same file serves from cache (no download)
- [ ] Changed file (different ETag) re-downloads
- [ ] Eviction works when over size limit
- [ ] "Clear Cache" removes all cached files

---

## Phase 8: LastSessionStore

### What to create

**File: `LocalCloudBrowser/App/LastSessionStore.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/App/LastSessionStore.swift`

```
LastSessionState: Codable
  - s3BucketName: String?
  - s3Path: [String]?

LastSessionStore: enum (static namespace)
  - isEnabled: Bool (reads AppPreferences.restoreLastSessionKey)
  - load() → LastSessionState?
  - save(_ state: LastSessionState)
  - saveS3Bucket(_ name: String?)
  - saveS3Path(_ components: [String])
  - clearSubResources()
  — Storage: UserDefaults key "lastSessionState", JSON encoded
```

### Where to wire
- **S3ModuleView:** On appear, if LastSessionStore.isEnabled, load and set `restoreBucketName`/`restorePath`
- **S3ObjectBrowserView:** On navigate, call `LastSessionStore.saveS3Bucket()` and `saveS3Path()`
- **S3BucketListView:** On bucket selection, call `LastSessionStore.saveS3Bucket()`
- **App launch:** If enabled, load state. If disabled, clearSubResources().
- **SettingsView:** Toggle "Open where I left off" bound to AppPreferences.restoreLastSessionKey

### Checkpoint
- [ ] Navigating to bucket/folder saves state
- [ ] Relaunch restores to saved bucket + path
- [ ] Toggle off → clears saved state
- [ ] Works across connection profile switches

---

## Phase 9: AppPreferences Expansion & Settings View

### What to modify

**File: `LocalCloudBrowser/App/AppPreferences.swift`** (MODIFY — verify existing, add missing keys)

Add keys:
```swift
static let restoreLastSessionKey = "restoreLastSession"
static let doubleClickActionKey = "doubleClickAction"
static let previewCacheEnabledKey = "previewCacheEnabled"
static let previewCacheSizeLimitMBKey = "previewCacheSizeLimitMB"
static let defaultPreviewCacheSizeLimitMB = 500
static let previewTempSubfolder = "localcloudbrowser-preview"
```

Add computed properties:
```swift
static var previewCacheEnabled: Bool
static var previewCacheSizeLimitMB: Int
static var previewTempDirectory: URL
static func cleanPreviewTempDirectory()
```

**File: `LocalCloudBrowser/Settings/SettingsView.swift`** (MODIFY)

Add/enhance sections:
```
Section "Session":
  Toggle "Open where I left off" (@AppStorage restoreLastSessionKey)

Section "Behavior":
  Picker "Double-click file action": preview | metadata | download

Section "Auto-Refresh":
  Picker "Refresh interval": Off(0), 1s, 3s, 5s, 10s, 30s, 60s

Section "Quick Look":
  Stepper "Preview size limit: X MB" (1...50)
  Toggle "Cache previewed files"
  [if cache enabled]:
    Stepper "Cache size limit: X MB" (50...1000, step 50)
    HStack: "Currently using X MB" + "Clear Cache" button
```

Frame: `width: 500, height: dynamic (420-500 based on cache toggle)`

### Checkpoint
- [ ] All preferences persist to UserDefaults
- [ ] Settings UI reflects current values
- [ ] Double-click action changes behavior in object browser
- [ ] Cache toggle enables/disables cache section

---

## Phase 10: S3Service Upload Path Refactor

### What to modify

**File: `LocalCloudBrowser/Modules/S3/S3Service.swift`** (MODIFY)

Current state:
- `putObjectMultipart()` does inline multipart with FileHandle + TaskGroup
- `uploadObject()` routes based on 20MB threshold
- Signs on main thread via CloudClient

Target state:
- `uploadFile(bucket:key:fileURL:contentType:progress:)` delegates to StreamingUploader
- CloudClient.makeSigningContext() provides Sendable snapshot
- Threshold: 5MB (single PUT) vs multipart (8MB default parts)
- StreamingUploader handles all background work

Changes:
1. Add `uploadFile()` method that:
   ```swift
   func uploadFile(bucket: String, key: String, fileURL: URL, 
                   contentType: String, progress: @Sendable (Int64, Int64) -> Void) async throws {
       let context = client.makeSigningContext()
       let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as! Int64
       let uploader = StreamingUploader()
       let plan = MultipartUploadPlan.plan(fileSize: fileSize)
       if plan.isMultipart {
           try await uploader.uploadMultipart(fileURL: fileURL, signingContext: context, 
                                               bucket: bucket, key: key, contentType: contentType,
                                               plan: plan, progress: progress)
       } else {
           try await uploader.uploadSingleFile(fileURL: fileURL, signingContext: context,
                                                bucket: bucket, key: key, contentType: contentType,
                                                progress: progress)
       }
   }
   ```
2. Keep existing `putObject(bucket:key:data:contentType:)` for small in-memory objects
3. Keep existing `putObjectMultipart()` as fallback or remove if fully replaced

### Checkpoint
- [ ] Small file upload (< 5MB) works via single PUT
- [ ] Large file upload (> 5MB) works via multipart
- [ ] Progress callback reports cumulative bytes
- [ ] Upload succeeds against LocalStack and MinIO

---

## Phase 11: S3ObjectBrowserView Integration

### What to modify

**File: `LocalCloudBrowser/Modules/S3/S3ObjectBrowserView.swift`** (MODIFY — largest change)

#### Remove
- `folderUploadProgress: (current: Int, total: Int)?`
- `folderUploadTask: Task<Void, Never>?`
- Inline folder upload logic (replace with TransferManager.enqueueUploads)

#### Add state
```swift
@EnvironmentObject private var transferManager: TransferManager
@State private var showUploadComplete = false
@State private var showTransferCancelled = false
@State private var showTransferFailed = false
@State private var failedTransferCounts: (failed: Int, total: Int) = (0, 0)
@State private var showCompletionPause = false
@State private var completionPauseCounts: (completed: Int, total: Int) = (0, 0)
```

#### Wire upload flow
Replace `uploadFolderURLs(from:)` inline logic with:
```swift
transferManager.enqueueUploads(files) { file in
    try await service.uploadFile(bucket: bucket.name, key: file.s3Key,
                                  fileURL: file.localURL, contentType: file.contentType,
                                  progress: { bytes, total in
        transferManager.updateProgress(id: file.id, bytesTransferred: bytes, totalBytes: total)
    })
}
```

#### Wire onFileUploaded callback
In `.onAppear` or `.task`:
```swift
transferManager.onFileUploaded = { [weak self] bucket, key, size in
    appendUploadedObject(key: key, size: size, prefix: currentPrefix)
}
```
This appends a temporary row with "Just now" date, avoiding per-file LIST requests.

#### Wire queue drain refresh
Listen to `transferManager.lastBatchResult`:
```swift
.onChange(of: transferManager.lastBatchResult) { result in
    if result == .completed { loadObjects(force: true) }
}
```

#### Add UI components
1. UploadQueueBanner — between breadcrumb and table
2. TransferPillView — `.overlay(alignment: .bottom)` on table with `.padding(.bottom, 12)`
3. StatusBarTransferIndicator — in status bar HStack

#### Update drag-drop handler
Replace direct upload with `transferManager.enqueueUploads()`.

### Checkpoint
- [ ] Drag-drop enqueues to TransferManager
- [ ] Upload File/Folder toolbar actions enqueue to TransferManager
- [ ] Progress pill shows during upload
- [ ] Queue banner shows per-bucket status
- [ ] Completed files appear in table with "Just now"
- [ ] Queue drain triggers full refresh
- [ ] folderUploadProgress/folderUploadTask fully removed

---

## Phase 12: Keyboard Navigation & Shortcuts

### What to modify

**File: `LocalCloudBrowser/Modules/S3/S3ObjectBrowserView.swift`** (MODIFY)

Add keyboard handlers:
```swift
.onKeyPress(.rightArrow) {
    // If single folder selected → navigate into it
    guard let item = singleSelectedFolder else { return .ignored }
    navigate(to: pathComponents + [item.name])
    return .handled
}

.onKeyPress(.leftArrow) {
    // Navigate to parent (if not at root)
    guard !pathComponents.isEmpty else { return .ignored }
    navigateToParent()
    return .handled
}

.keyboardShortcut("[", modifiers: .command)  // Navigate back
.keyboardShortcut("]", modifiers: .command)  // Navigate forward
```

**File: `LocalCloudBrowser/App/S3FocusedValues.swift`** (MODIFY)

Add:
```swift
struct S3SelectAllActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
extension FocusedValues {
    var s3SelectAllAction: (() -> Void)? { ... }
}
```

**File: `LocalCloudBrowser/Modules/S3/S3ModuleView.swift`** (MODIFY)

Add pane focus switching:
```swift
.onKeyPress(.leftArrow, modifiers: .command) {
    listPaneFocusTrigger += 1
    return .handled
}
.onKeyPress(.rightArrow, modifiers: .command) {
    detailPaneFocusTrigger += 1
    return .handled
}
```

### Checkpoint
- [ ] Right arrow opens selected folder
- [ ] Left arrow navigates to parent
- [ ] Cmd+[ goes back in history
- [ ] Cmd+] goes forward in history
- [ ] Cmd+A selects all rows
- [ ] Cmd+Left/Right switches pane focus

---

## Phase 13: ContentView & App-Level Integration

### What to modify

**File: `LocalCloudBrowser/Navigation/ContentView.swift`** (MODIFY)

Add to toolbar:
```swift
ToolbarItem(placement: .automatic) {
    TransferToolbarButton()
}
```

Add transfer warning on profile switch:
```swift
@State private var showTransferWarning = false
@State private var pendingSwitchProfile: ConnectionProfile?

// Before switching profile:
if transferManager.hasActiveTransfers {
    pendingSwitchProfile = profile
    showTransferWarning = true
} else {
    switchToProfile(profile)
}

.alert("Transfers in Progress", isPresented: $showTransferWarning) {
    Button("Cancel Transfers & Switch", role: .destructive) {
        transferManager.cancelAll()
        if let profile = pendingSwitchProfile { switchToProfile(profile) }
    }
    Button("Cancel", role: .cancel) {}
}
```

**File: `LocalCloudBrowser/App/LocalCloudBrowserApp.swift`** (MODIFY — the @main App)

Add AppDelegate for quit prevention:
```swift
class AppDelegate: NSObject, NSApplicationDelegate {
    weak var transferManager: TransferManager?
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let tm = transferManager, tm.hasActiveTransfers else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Uploads in Progress"
        alert.informativeText = "There are active file transfers. Quitting will cancel them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel Transfers & Quit")
        alert.addButton(withTitle: "Don't Quit")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
```

Inject TransferManager as environment object on the main window.

### Checkpoint
- [ ] TransferToolbarButton visible in main toolbar
- [ ] Profile switch warns when transfers active
- [ ] Quitting during transfers shows confirmation dialog
- [ ] TransferManager available as @EnvironmentObject throughout app

---

## Phase 14: sortedRows Stored Computation

### What to modify

**File: `LocalCloudBrowser/Modules/S3/S3ObjectBrowserView.swift`** (MODIFY)

Replace computed properties:
```swift
// REMOVE these computed properties:
var sortedRowItems: [RowItem] { ... }
var filteredRowItems: [RowItem] { ... }

// ADD stored state:
@State private var sortedRows: [RowItem] = []
```

Add recomputation function:
```swift
private func recomputeSortedRows() {
    // Same logic as current computed property but stored
    let base = isSearchActive ? filteredSearch : currentPageRows
    let sorted = base.sorted(using: sortOrder)
    // Prepend parent row if not at root and not searching
    if !pathComponents.isEmpty && !isSearchActive {
        sortedRows = [parentRow] + sorted
    } else {
        sortedRows = sorted
    }
}
```

Wire `.onChange` triggers (7 inputs):
```swift
.onChange(of: objects) { recomputeSortedRows() }
.onChange(of: prefixes) { recomputeSortedRows() }
.onChange(of: sortOrder) { recomputeSortedRows() }
.onChange(of: searchQuery) { recomputeSortedRows() }
.onChange(of: pathComponents) { recomputeSortedRows() }
.onChange(of: allPageObjects) { recomputeSortedRows() }
.onChange(of: allPagePrefixes) { recomputeSortedRows() }
```

### Why this matters
- Current: computed properties recalculate on EVERY view body evaluation
- With 1000+ objects, this causes visible lag during scroll/selection
- Stored computation only recalculates when inputs actually change

### Checkpoint
- [ ] Table renders correctly with sorted rows
- [ ] Sorting by column header updates rows
- [ ] Search filters correctly
- [ ] Navigation between folders updates rows
- [ ] Performance improvement measurable with large listings

---

## Phase 15: Empty State Context Menus & Swipe-to-Delete

### What to modify

**File: `LocalCloudBrowser/Modules/S3/S3ObjectBrowserView.swift`** (MODIFY)

Add context menu on empty table area:
```swift
// On the table or empty state view:
.contextMenu {
    if !appState.isReadOnly {
        Button("Create Folder") { showCreateFolder = true }
        Divider()
        Button("Upload File") { toolbarState.pendingAction = .uploadFile }
        Button("Upload Folder") { toolbarState.pendingAction = .uploadFolder }
        if appState.s3Clipboard?.sourceBucket != nil {
            Divider()
            Button("Paste") { performPaste() }
        }
    }
}
```

**File: `LocalCloudBrowser/Modules/S3/S3BucketListView.swift`** (MODIFY)

Add swipe-to-delete:
```swift
.swipeActions(edge: .trailing, allowsFullSwipe: false) {
    Button(role: .destructive) {
        bucketsToDelete = [bucket]
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

**File: `LocalCloudBrowser/Modules/S3/S3ToolbarState.swift`** (MODIFY)

Add `.uploadFolder` to Action enum if not present.

### Checkpoint
- [ ] Right-click on empty object browser shows Create Folder, Upload, Paste
- [ ] Swipe left on bucket row shows red Delete button
- [ ] Upload Folder appears as separate toolbar menu option

---

## Phase 16: S3BrowserWindow (Floating Detached Browser)

### What to create

**File: `LocalCloudBrowser/Modules/S3/S3BrowserWindow.swift`** (NEW)
Port from: `S3BrowserApp/Sources/S3Browser/S3/S3BrowserWindow.swift`

```
S3BrowserTarget: Codable, Hashable
  - bucket: String
  - prefix: String?

S3BrowserWindow: View
  - target: S3BrowserTarget
  - Creates standalone S3ObjectBrowserView with given bucket/prefix
  - Title: "bucket" or "bucket — prefix"
```

### Where to wire
- **App @main:** Add secondary WindowGroup:
  ```swift
  WindowGroup(id: "s3-browser", for: S3BrowserTarget.self) { $target in
      if let target { S3BrowserWindow(target: target) }
  }
  ```
- **Context menu** in S3ObjectBrowserView: "Open in New Window" action opens this window

### Checkpoint
- [ ] "Open in New Window" context menu item works
- [ ] New window shows correct bucket/prefix
- [ ] Multiple windows can be open simultaneously

---

## Phase 17: Unit Tests

### Test files to create/modify

**File: `Tests/LocalCloudBrowserTests/TransferTypesTests.swift`** (NEW)
8 tests:
- Transfer direction values
- Transfer state equality (including .failed associated value)
- isFinished for all 5 states
- fractionCompleted: zero total → 0.0
- fractionCompleted: normal range
- fractionCompleted: capped at 1.0
- fractionCompleted: large values (overflow safety)
- fractionCompleted: negative bytes → 0.0

**File: `Tests/LocalCloudBrowserTests/RetryPolicyTests.swift`** (NEW)
11 tests:
- Exponential backoff calculation (attempt 0, 1, 2, 3)
- Max delay capping
- Jitter within bounds (±25%)
- shouldRetry: 500 → retry
- shouldRetry: 502, 503, 504 → retry
- shouldRetry: 400, 403, 404 → doNotRetry
- shouldRetry: network error → retry
- shouldRetry: max retries exceeded → doNotRetry
- Default policy values
- No retry policy values
- Non-negative delay guarantee

**File: `Tests/LocalCloudBrowserTests/MultipartUploadPlanTests.swift`** (NEW)
7 tests:
- Small file (< 5MB) → single, not multipart
- Exactly 5MB → single
- Over 5MB → multipart with correct parts
- Part count and size calculations
- Offset contiguity (no gaps)
- Large file (100GB) scales part size to stay under 10k parts
- completeMultipartXML generates valid XML with sorted parts

**File: `Tests/LocalCloudBrowserTests/PreviewCacheTests.swift`** (NEW)
16 tests:
- Codable round-trip preservation
- Deterministic disk filename
- Collision-free filenames for different keys
- Extension preservation
- Index save/load round-trip
- Corrupt index → graceful empty
- Lookup hit
- Lookup miss (different key)
- Lookup miss (file deleted from disk)
- Upsert new entry
- Upsert replaces existing
- LRU eviction (oldest first)
- Orphan pruning
- Total size calculation (existing files only)
- Clear all removes directory
- Empty index edge cases

**File: `Tests/LocalCloudBrowserTests/ContentMD5Tests.swift`** (NEW)
4 tests:
- MD5 of empty data matches known hash
- MD5 of known input matches expected
- Base64 header format is valid
- Consistent across multiple calls

### Checkpoint
- [ ] All tests pass with `swift test` or xcodebuild test
- [ ] Test count: 46+ new tests
- [ ] No flaky tests (deterministic, no network)

---

## Phase 18: Final Verification & Cross-Check

### Verification checklist

**Transfer System:**
- [ ] Drag-drop 10 files → enqueues, processes 6 concurrently, shows progress
- [ ] Upload File toolbar → single file upload with progress pill
- [ ] Upload Folder toolbar → recursive enumeration, queue-based upload
- [ ] Transfer popover shows all items with per-item progress
- [ ] Cancel single transfer works
- [ ] Cancel all transfers works
- [ ] Failed transfer shows in popover with error
- [ ] Queue drain triggers object list refresh
- [ ] Per-file completion appends row with "Just now"

**Retry System:**
- [ ] Network timeout → retries with backoff
- [ ] 500 error → retries up to 3 times
- [ ] 403 error → no retry

**Preview Cache:**
- [ ] First Quick Look downloads and caches
- [ ] Second Quick Look serves from cache
- [ ] Changed ETag re-downloads
- [ ] Clear Cache empties cache
- [ ] Cache size limit triggers eviction

**Auto-Refresh:**
- [ ] Interval picker works in Settings
- [ ] Countdown visible in toolbar
- [ ] Refresh fires automatically
- [ ] Pauses during loading

**Session Restore:**
- [ ] "Open where I left off" toggle in Settings
- [ ] Navigating saves state
- [ ] Relaunch restores bucket + path

**Keyboard Navigation:**
- [ ] Right arrow opens folder
- [ ] Left arrow goes to parent
- [ ] Cmd+[/] for history
- [ ] Cmd+A selects all
- [ ] Spacebar previews

**App Lifecycle:**
- [ ] Quit during transfers shows warning
- [ ] Profile switch during transfers shows warning
- [ ] Transfer toolbar button with badge

**UI Polish:**
- [ ] sortedRows performance improvement
- [ ] Empty state context menus
- [ ] Swipe-to-delete on buckets
- [ ] Upload Folder menu item

**Settings:**
- [ ] All new preferences visible and functional
- [ ] Double-click action picker works
- [ ] Cache settings show/hide based on toggle

**Tests:**
- [ ] All existing tests still pass
- [ ] 46+ new tests pass
- [ ] No compiler warnings

### Update CLAUDE.md
Add architecture notes for:
- TransferManager queue system
- StreamingUploader background signing
- Preview cache ETag flow
- AutoRefreshManager timer pattern
- sortedRows performance pattern
