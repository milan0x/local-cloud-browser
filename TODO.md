# TODO — Deferred from 2026-06-11 audit

Items found in the full code/UX audit that we decided to address later.
(The critical fixes — AWS rerouting, DynamoDB cell corruption, read-only upload
bypass, SQS receipt handles, `+` query encoding, bucket policy, active-connection
delete, S3 navigation race — were fixed on 2026-06-11.)

## Medium bugs

- [ ] **Read-only default**: `isReadOnlyKey` is not in `register(defaults:)` (`LocalCloudBrowserApp.swift:32`), so fresh installs start in write mode despite the documented "read-only on by default". One-line fix — deliberately deferred.
- [ ] **Lambda `Invoke` whitelisted as read-only** (`CloudClient.swift` lambdaReadActions) — invoking runs arbitrary code; remove from whitelist or confirm explicitly. Related: SQS `ReceiveMessage` increments ApproximateReceiveCount and can push messages to a DLQ on real AWS.
- [ ] **Mutations retried on network errors** (`RetryExecutor.swift:41`) — a timeout after the server processed SendMessage/Publish/PutItem replays it. Use `.noRetry` for non-idempotent actions.
- [ ] **SafetyGuard hostname spoofing** (`SafetyGuard.swift:34`) — `10.0.0.1.evil.com` classifies as local (non-numeric labels dropped from the IP check). Also `localhost.localstack.cloud` is classified non-local (spurious warning banner, detection refuses to probe).
- [ ] **Move-to-same-folder via Browse picker deletes the only copy** (`S3ObjectBrowserView.swift:414` + `S3Service.moveObject` = copy+delete). Guard `destinationKey != sourceKey` in performMove/performMoveToBucket/moveFolder.
- [ ] **Silent 10k cap on folder operations** (`S3Service.swift:69,84`) — rename/move/empty/zip of >10k-object folders silently truncates. Propagate a `truncated` flag; warn/refuse on mutating ops.
- [ ] **Partial delete failures swallowed** (`S3Service.deleteObjects` → callers discard the Bool) — surface "N of M deleted".
- [ ] **One shared `longRunningTask`** in S3ObjectBrowserView — unrelated operations cancel each other (drop upload cancels folder delete, etc.). Per-operation task handles.
- [ ] **DynamoDB Binary attrs convert B→S on edit round-trip** (`DynamoDBPutItemView.swift:370` decomposeAttributeValue). Add binary cases or preserve untouched attributes verbatim.
- [ ] **DynamoDB FilterExpression can never work** (`DynamoDBItemBrowserView.swift:677`) — expressionAttributeValues/Names never passed; expressions with literals always fail.
- [ ] **5 services missing pagination** — Transcribe (default page is 5 jobs!), APIGateway, SecretsManager, KMS, Redshift. Copy the `listXxxPage` + loop pattern from IAMService.
- [ ] **Secrets Manager delete hardcodes ForceDeleteWithoutRecovery=true** — offer the 7–30 day recovery window on non-local endpoints.
- [ ] **Route53 weighted-record delete always fails** — ChangeBatch omits Weight/SetIdentifier (`Route53Service.swift:116-141`).
- [ ] **Health-check loop never stops** after last profile deleted (`AppState` has no stopHealthCheck); can flip status back to "connected" for a deleted endpoint.
- [ ] **MinIO switch doesn't reset unsupported selectedRoute** — SQS view keeps firing requests at MinIO; sidebar and detail pane desync.
- [ ] **`forceDeleteTask` survives connection switches** (`S3BucketListView.swift:326`) — cancel on connectionVersion change and onDisappear.
- [ ] **Quit path doesn't abort multipart uploads** ("Cancel Transfers & Quit" returns `.terminateNow` without cancelAll) — orphaned billable parts on AWS.
- [ ] Low tail: SQS delete uses per-row trash with stale search-page lookups (M7: search-mode per-row actions look up current-page `objects` instead of `objectsByKey`); upload-batch reconciliation `.onChange` attached to moveToBucketSheet instead of mainContent (M6); QuickLook temp path for keys ending in `..` + missing `defer { handle.close() }` (S3QuickLookManager); byte-by-byte AsyncBytes on MainActor for big downloads; SigV4 canonical query sorted as joined strings not by key; `request.url!` force-unwrap in signer; mailto body breaks on `&` (FeedbackView); ⌘R registered twice; auto-detection runs twice per connect; region picker bypasses MinIO us-east-1 lock; hardcoded "1.0.0" in About; QR regenerated every render with fresh CIContext; Keychain migration flag set even if re-encode fails; Route53 pagination params not URL-encoded; SNS/SQS CLI export unquoted ARNs; StepFunctions Stop Execution has no confirmation; CloudWatch bad timestamps render as "now"; KMS list fails wholesale on one bad key.

## UX / design improvements

- [ ] **Welcome sheet still shows paid-era copy** (`WelcomeView.swift`) — "What's included for free… Create up to 5 resources per service". Rewrite to three honest rows; use it to teach the read-only lock. Also: hand-rolled blue pill → `.borderedProminent`.
- [ ] **Retire floating heart + one-item "Donation" menu** — move "Donate…" to the app menu + Help menu; optional quiet link on the welcome pane. Keep the DonationView sheet. Rename "Support development" (collides with the AWS Support module).
- [ ] **Invert safety signaling** — writes-enabled on a non-local endpoint should be the loud state (red open lock / "Writes enabled" badge), read-only the calm one.
- [ ] **Empty states have no next action** — add optional `action` to shared `EmptyStateView`, thread through `ListLoadingContent` → all 28 services get a "Create X" button in one change (hide when read-only).
- [ ] **Small wins**: drop "GUI" from window title (`LocalCloudBrowserApp.swift:93`, `ContentView.swift:185`); native menu checkmarks (Picker) + ⌘1–⌘9 profile switching in Connection menu; `.help("Not supported by MinIO")` on dimmed sidebar rows; hide IAM permission-builder toolbar key on local endpoints; drop duplicate S3 toolbar refresh.
- [ ] Reconsider per-row Actions column in S3 table (web-console pattern; at minimum drop the per-row trash). Judgment call.
- [ ] Transcribe is categorized under "Management & Governance" in `Route.swift:79` — it's an ML service.

## macOS 27 "Golden Gate" (September 2026)

- Announced WWDC26 (June 8). Refinement year: user-controllable Liquid Glass transparency slider, less-rounded corners, edge-to-edge sidebars with colored icons, calmer toolbars — system aesthetic moves toward this app's look.
- **Adoption = recompile with Xcode 27** (beta out; requires macOS Tahoe 26.4+ on build Mac; GA ~Sept). Keep macOS 14 deployment target — Xcode 27 supports targets back to 12. No opt-out (`UIDesignRequiresCompatibility` ignored on 27 SDK), but Developer ID/DMG distribution has no SDK deadline.
- New APIs worth gating behind `#available(macOS 27, *)`: toolbar `visibilityPriority` / `toolbarOverflowMenu` (dense per-service toolbars), `reorderable()` containers, faster `@State`/ContentBuilder pipeline. Nothing replaces the NSViewRepresentable text editors yet.
- When adopting: test the transparency slider at both extremes against dense tables/sidebar; verify custom backgrounds don't fight glass materials. Swift 6.4 compiler — no language-mode migration needed.

## Housekeeping

- [ ] `donation/usdt.jpeg` is untracked — commit or gitignore.
