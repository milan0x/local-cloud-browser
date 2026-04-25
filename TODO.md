# TODO

## Demo Polish (Pre-LocalStack Preview)

- [ ] Reword or remove "Mock API — cases may not persist across restarts" banner (`SupportCaseListView.swift:99`) — looks unfinished
- [ ] Make EC2 simulation message provider-aware instead of hardcoding "LocalStack" (`EC2EntityListView.swift:58`)
- [ ] Polish CloudWatch empty state copy — "Use Put Metric Data to create test data" sounds developer-facing (`CloudWatchMetricListView.swift:84`)
- [ ] Replace `print()` with `os.log` in `Log.swift:20` — shows in Xcode console during demos
- [ ] Update DESIGN.md title from "LocalStack Navigator" to "Local Cloud Browser"
- [ ] Toolbar transfer icon: when item count hits ~10K the alignment overflows the toolbar slot. Format counts compactly — `9999` stays as-is, `10000+` becomes `10K`, `10100` becomes `10.1K`, etc. Use `NumberFormatter` with `.compact` style or a small custom formatter so the badge stays narrow.

## Live Monitoring (Menu Bar + Main App)

### Menu Bar Watch Mode

A persistent macOS menu bar item (like Docker Desktop or iStat Menus) that keeps developers aware without switching to the app.

- [ ] **Menu bar text ticker** — A wide menu bar item that displays event text directly in the macOS menu bar, not just an icon. Shows full event descriptions like `S3 → photo.jpg uploaded (1.2 MB)` right in the bar. Events rotate automatically with a fade/slide transition — `S3 → photo.jpg uploaded (1.2 MB)` transitions to `SQS → 1 message in orders-queue` transitions to `SNS → alert published to notifications`. Developers see activity passively while working in any app — no clicking, no hovering, just glance at the menu bar. When idle, shows a compact status like `LCB · watching · 3 services` or the app icon.
- [ ] **Menu bar dropdown — event list** — Click the menu bar text to expand a dropdown with the full scrolling list of recent events. One-line entries with timestamps, expandable for details (payload size, object key, queue name). Quick actions inline: "Open in app", "Copy ARN".
- [ ] **Menu bar dropdown — activity log** — Below the live ticker, a scrollable historical log grouped by time window ("2:00 – 2:15 PM"). Summary lines like: "3 files uploaded to `uploads/`, 5 messages sent to `orders-queue`". Filter by service type. Answers "what happened while I wasn't looking."
- [ ] **Watch mode toggle** — Enable/disable watching from both the menu bar dropdown and the main app. When enabled, polls services at an adaptive interval (faster during active periods, slower when idle). When disabled, the menu bar icon stays but goes dormant.

### Main App Monitoring

- [ ] **Event stream panel** — In-app real-time feed of all activity across services. One unified timeline. Developers `aws s3 cp` in terminal and instantly see it appear. *Most visual, most "wow", hardest to get elsewhere — top priority for the demo.*
- [ ] **Lambda log tail** — Stream CloudWatch Logs for a Lambda function live, like `docker logs -f` but for Lambda. No more switching to CLI to read logs.
- [ ] **Queue depth badges** — Menu bar shows SQS queue depths with color coding (green/yellow/red). Developers see message buildup without checking.

## Developer Workflow Acceleration

- [ ] **Seed data snapshots** — Save the current state of all services as a named snapshot ("checkout-flow-test-data"), restore it in one click. LocalStack has a persistence/state feature but no GUI for it. *Solves a real daily pain point — no existing GUI for this.*
- [ ] **Quick actions palette** — Cmd+K spotlight-style launcher: "purge queue orders-queue", "tail lambda process-order", "clear bucket uploads". Power users never leave the keyboard.
- [ ] **Request inspector** — Intercept and display the actual AWS API calls hitting LocalStack, with request/response bodies. Like Proxyman but specifically for AWS SDK calls. Huge for debugging "why isn't my code working." *"Proxyman for AWS" is immediately understood — high demo value.*
- [ ] **Hot reload trigger** — Detect when `docker-compose restart localstack` or `localstack start` happens and auto-reconnect + refresh all views. Developers restart LocalStack constantly and currently have to manually reconnect. Could poll the health endpoint or watch Docker events.
- [ ] **Resource templates** — One-click "create SQS queue + DLQ + redrive policy" or "S3 bucket + event notification → SQS". The common multi-resource setups that developers create dozens of times a day, bundled into single actions.
- [ ] **CLI command copy** — For any resource shown in the GUI, copy the equivalent `awslocal` CLI command. Developers often need to script what they just did manually. Every detail view gets a "Copy as CLI" button.
- [ ] **Init hook generator** — Generate `docker-compose` init hooks / `ready.d` scripts from the current LocalStack state. "I set everything up manually in the GUI, now give me the bootstrap script so my teammates get the same setup."

## Check & Validate

- [ ] **Assertion mode** — Define expected state ("queue X should have 0 messages", "bucket Y should contain file Z") and get a green/red dashboard. Manual integration test verification without writing test assertions. Save assertion sets per project.
- [ ] **Before/after diff** — Snapshot state across all services, run your code, see exactly what changed. Like a git diff but for cloud resources. Shows created/modified/deleted resources with payload diffs.
- [ ] **Payload validator** — Paste a JSON schema, then every message in a queue or object in a bucket gets validated against it. Catch malformed payloads instantly. Flag mismatches inline with the validation error.

## Team Collaboration

- [ ] **Shared connection profiles** — Export/import connection configs so a team all points at the same LocalStack setup. Drop a `.lcb` file in the repo.
- [ ] **Infrastructure blueprint** — Show what's deployed (queues, buckets, tables, functions) as a visual map with connections. "This SNS topic fans out to these 3 SQS queues which trigger these Lambdas."
- [ ] **Diff against CloudFormation/CDK** — Compare what's actually in LocalStack vs what the IaC template says should be there. Catch drift instantly.

## Debugging

- [ ] **Message tracing** — Follow a message from SNS publish → SQS delivery → Lambda trigger → DynamoDB write. End-to-end visibility for event-driven architectures. *Visual tracing for event-driven systems is genuinely unique — nothing else does this well.*
- [ ] **Replay failed messages** — Pick a failed SQS message from DLQ, inspect it, edit the payload, and re-send it to the source queue.
- [ ] **Environment health dashboard** — One screen showing: are all services healthy, what's the state, when was LocalStack last restarted, any errors in the logs. *Simplest to build, great first-impression screen.*
- [ ] **LocalStack Pro feature detection** — Show which features require Pro vs Community edition, so developers don't waste time debugging something that simply isn't supported on their tier. Surface this contextually when a user tries to use an unsupported feature.

## Demo Priority Order

1. **Event stream** — most visual, hardest to get elsewhere
2. **Seed data snapshots** — daily pain point, no existing GUI
3. **Request inspector** — "Proxyman for AWS" is immediately understood
4. **Environment health dashboard** — simplest to build, great first impression
