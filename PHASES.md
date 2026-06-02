# Local Cloud Browser — Implementation Phases (Free-Tier Remaining Services)

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

## Phase 4 — Elasticsearch ✅

Covered by existing OpenSearch module — domains are shared. OpenSearch module includes cluster health badges, index browser with doc count/size, "Open in Browser" button, and Elasticsearch version support.

---

## Phase 5 — AWS Config ✅

Implemented: Tabbed HSplitView (Recorders/Delivery Channels), recorder CRUD with status badges (RECORDING/STOPPED), start/stop toggle, delivery channel CRUD (S3 bucket, SNS topic, frequency picker), JSON 1.1 protocol via StarlingDoveService, session restore for tab + recorder + channel.

---

## Phase 6 — Resource Groups ✅

Implemented: HSplitView (list + detail), REST-JSON protocol (POST to /groups-list, /get-group, /get-group-query, etc.), resource group CRUD, tag filter builder with dynamic rows, query viewer (tag filters + resource type filters), matched resources list with color-coded service badges (S3/Lambda/DynamoDB/EC2/SQS/SNS/RDS/IAM), session restore.

---

## Phase 7 — Transcribe ✅

Implemented: HSplitView (job list + detail), JSON 1.1 protocol via `Transcribe.<Action>`, job CRUD (Start/List/Get/Delete), status badges (QUEUED/IN_PROGRESS/COMPLETED/FAILED), audio format badges (WAV/MP3/FLAC/OGG/AMR/WEBM/MP4), 33-language selector, create form with S3 media URI + language + format + optional output bucket, detail pane with job info + media URIs + transcript viewer, transcript fetched from S3 output URI, auto-refresh polling for in-progress jobs, session restore.

---

## Phase 8 — AWS Support API ✅

Implemented: HSplitView (case list + detail), JSON 1.1 protocol via `AWSSupport_20130415.<Action>`, case CRUD (CreateCase/DescribeCases/ResolveCase), 5 status badges (unresolved/pending/resolved/reopened/in-progress), 5 severity levels (low/normal/high/urgent/critical), communications viewer, create case form with subject + body + service/category/severity, resolve action with confirmation, session restore.

---

## Summary

| Phase | Service | Functional? | Visual | Complexity | Value |
|-------|---------|-------------|--------|------------|-------|
| 1 ✅ | Step Functions | Full execution | ★★★★★ | High | Highest |
| 2 ✅ | EC2 | Mock CRUD | ★★★★☆ | High | High |
| 3 ✅ | EventBridge Scheduler | Mock (no exec) | ★★★☆☆ | Medium | Medium-High |
| 4 ✅ | Elasticsearch | Real clusters | ★★★☆☆ | Medium | Medium |
| 5 ✅ | AWS Config | Mock CRUD | ★★☆☆☆ | Low | Medium-Low |
| 6 ✅ | Resource Groups | Tag queries | ★★☆☆☆ | Low | Low |
| 7 ✅ | Transcribe | Real transcription | ★★★☆☆ | Medium | Low |
| 8 ✅ | Support API | Mock only | ★☆☆☆☆ | Low | Lowest |
