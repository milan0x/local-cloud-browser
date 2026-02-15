# LocalStack Navigator — Implementation Phases (Free-Tier Remaining Services)

> 7 services remain from the LocalStack Community (free) tier.
> Each phase = one service module, ordered by implementation value.

---

## Phase 1 — Step Functions ✅

Implemented: HSplitView + tabbed detail (Definition/Executions), 3-level drill-down, 5 status badges, 8 event type badges, ASL JSON viewer, start/stop execution.

---

## Phase 2 — EC2 ✅

Implemented: Tabbed HSplitView (Instances/Security Groups/Key Pairs), instance CRUD with state badges, security group rules editor, key pair creation with private key display, mock CRUD info banner, custom EC2XMLParser.

---

## Phase 3 — EventBridge Scheduler ✅

Implemented: Tabbed EventBridge module (Events | Schedules), schedule group CRUD, schedule CRUD with cron/rate/one-time expressions, human-readable expression preview, next 5 occurrences computation, target type badges (Lambda/StepFunctions/SQS/SNS), enable/disable toggle, flexible time window, warning banner for non-executing schedules, session restore for tab + group + schedule.

---

## Phase 4 — Elasticsearch: Legacy Search Engine

**Protocol:** JSON 1.1 (management) + REST (engine). Domains shared with OpenSearch.

**LocalStack support:** `CreateElasticsearchDomain`, `DescribeElasticsearchDomain(s)`, `ListDomainNames`, `DeleteElasticsearchDomain`. Real single-node clusters.

**Layout:** HSplitView — domain list → detail. Reuse OpenSearch module patterns heavily.

**Features:**
- Domain CRUD with Elasticsearch version selector
- Endpoint URL (click-to-copy), version badge, cluster config
- Cluster health badge (green / yellow / red) via `_cluster/health`
- Index browser: list indices with doc count and size
- Note: "Domains are shared with OpenSearch Service"

**UI details:**
- Traffic-light health badge (green/yellow/red circle) — most intuitive status indicator
- Version badge distinguishing "Elasticsearch 7.10" vs "OpenSearch 2.x"
- "Open in Browser" button for live cluster REST API access
- Fastest build due to OpenSearch code reuse

---

## Phase 5 — AWS Config: Resource Configuration Tracker

**Protocol:** JSON 1.1, `X-Amz-Target: StarlingDoveService.<Action>`

**LocalStack support:** Configuration recorders (Put/Describe/Start/Stop/Delete), delivery channels (Put/Describe/Delete). Mock only — recorders do **NOT** capture changes.

**Layout:** Single-pane or simple HSplitView — two sections (Recorders + Delivery Channels), like STS.

**Features:**
- Recorder CRUD with status badges (RECORDING / STOPPED)
- Start/Stop toggle
- Delivery channel CRUD (S3 bucket, SNS topic, frequency)
- Warning banner: "Recorders are mocked — resource changes are NOT recorded"

**UI details:**
- Recording status badge: green "RECORDING" vs gray "STOPPED", single-click toggle
- Two-section layout in one pane — lightest layout in the app
- Delivery channel as "S3 bucket → SNS topic" flow display
- Quick implementation — palate cleanser between complex phases

---

## Phase 6 — Resource Groups: Tag-Based Organization

**Protocol:** JSON 1.1

**LocalStack support:** `CreateGroup`, `UpdateGroup`, `DeleteGroup`, `ListGroups`, `GetGroup`, `GetGroupQuery`. Tag-based queries (`TAG_FILTERS_1_0`).

**Layout:** HSplitView — group list → detail with query viewer + matched resources.

**Features:**
- Resource group CRUD
- Tag filter builder (dynamic key-value pair rows with +/- buttons)
- Matched resources list (ARN, type badge, tags)
- Query viewer (read-only JSON)

**UI details:**
- Tag filter builder: dynamic form with add/remove rows (like Lambda env vars)
- Service type badges on matched resources (S3/Lambda/DynamoDB/EC2) — cross-service color coding unique to this module
- Shallow interaction: create group → see matched resources, no drill-downs

---

## Phase 7 — Transcribe: Speech-to-Text Jobs

**Protocol:** JSON 1.1, `X-Amz-Target: Transcribe.<Action>`

**LocalStack support:** `StartTranscriptionJob`, `ListTranscriptionJobs`, `GetTranscriptionJob`, `DeleteTranscriptionJob`. Real transcription via Vosk (25+ languages, 7+ audio formats). Output to S3.

**Layout:** HSplitView — job list → detail with transcript viewer.

**Features:**
- Job list with status badges (QUEUED / IN_PROGRESS / COMPLETED / FAILED)
- Create form: name, S3 media URI, language selector (25+ languages), output bucket
- Job detail: status, input/output URIs, error message
- Transcript preview pane (scrollable formatted text)

**UI details:**
- Job status progression with auto-refresh polling — unique "waiting" state UX
- Transcript preview: large text area, breaks the JSON/table pattern — displays natural language
- Language selector: 25+ options, largest dropdown in the app
- Audio format badges (WAV / MP3 / FLAC / OGG)
- S3 URI fields could link to S3 module for cross-module navigation

---

## Phase 8 (Skipped) — AWS Support API

Mock-only ticket list (CreateCase/DescribeCases/ResolveCase). Minimal UI surface. Only for 100% coverage.

---

## Summary

| Phase | Service | Functional? | Visual | Complexity | Value |
|-------|---------|-------------|--------|------------|-------|
| 1 ✅ | Step Functions | Full execution | ★★★★★ | High | Highest |
| 2 ✅ | EC2 | Mock CRUD | ★★★★☆ | High | High |
| 3 ✅ | EventBridge Scheduler | Mock (no exec) | ★★★☆☆ | Medium | Medium-High |
| 4 | Elasticsearch | Real clusters | ★★★☆☆ | Medium | Medium |
| 5 | AWS Config | Mock CRUD | ★★☆☆☆ | Low | Medium-Low |
| 6 | Resource Groups | Tag queries | ★★☆☆☆ | Low | Low |
| 7 | Transcribe | Real transcription | ★★★☆☆ | Medium | Low |
| 8 | Support API | Mock only | ★☆☆☆☆ | Low | Lowest |
