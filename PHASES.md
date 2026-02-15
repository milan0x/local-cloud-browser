# LocalStack Navigator — Implementation Phases (Free-Tier Remaining Services)

> 7 services remain from the LocalStack Community (free) tier.
> Each phase = one service module, ordered by implementation value.

---

## Phase 1 — Step Functions: Workflow Orchestrator

**Service:** AWS Step Functions
**Protocol:** JSON 1.0, `X-Amz-Target: AWSStepFunctions.<Action>`
**Priority:** Highest

**Why it matters:**
Step Functions is one of the most heavily used serverless services — it orchestrates Lambda functions, coordinates DynamoDB reads/writes, fans out to SQS/SNS, and chains entire microservice workflows together. LocalStack provides **full execution support** in the free tier (state machines actually run), making this the richest module to implement.

**What LocalStack supports (free tier):**
- `CreateStateMachine`, `UpdateStateMachine`, `DeleteStateMachine`, `ListStateMachines`, `DescribeStateMachine`
- `StartExecution`, `DescribeExecution`, `ListExecutions`, `StopExecution`, `GetExecutionHistory`
- Real execution engine — state machines invoke Lambda, DynamoDB, SNS, SQS, etc.
- JSONata and Variables support
- Service integrations across all LocalStack services
- Mocked service testing with predefined responses

**Suggested UI layout:** HSplitView — state machine list (left) → tabbed detail (Definition / Executions tabs). Execution detail as drill-down with step history timeline, input/output JSON viewers, status badges (RUNNING / SUCCEEDED / FAILED / TIMED_OUT / ABORTED).

**Key features:**
- State machine CRUD with ASL (Amazon States Language) JSON editor
- Start execution with input JSON payload
- Execution history list with status badges and duration
- Execution detail: step-by-step state transitions, input/output per step
- State machine definition viewer (formatted JSON)

**Visual & Interaction Value:** ★★★★★ (highest in the entire app)
This is the most visually rich module we can build. The execution history is a **live, drillable timeline** — each execution fans out into individual state transitions (Task, Choice, Parallel, Wait, Pass, Fail, Succeed) that can be browsed step by step, each with its own input/output JSON. The interaction density is exceptional:
- **5 status badges** with distinct colors (RUNNING=blue, SUCCEEDED=green, FAILED=red, TIMED_OUT=orange, ABORTED=gray) — more visual variety than any existing module
- **3-level drill-down**: state machine list → execution list → step history (similar depth to CloudWatch Logs' groups→streams→events, but richer per level)
- **Dual JSON viewers** on the execution detail: input on top, output on bottom — users constantly compare what went in vs. what came out
- **Duration display** on each execution and each step — gives a performance-profiling feel
- **Type badges per state** (Task / Choice / Parallel / Wait / Map / Pass / Fail / Succeed) — color-coded chips that make the step history scannable at a glance
- **Start Execution button** with a JSON input editor makes this one of the few modules where users actively trigger real work and watch results flow in — high engagement loop (create → execute → inspect → tweak → re-execute)
- The ASL definition tab doubles as a **read-only code viewer** — a large formatted JSON block that benefits from monospace rendering and syntax structure

---

## Phase 2 — EC2: Virtual Infrastructure Dashboard

**Service:** Amazon Elastic Compute Cloud (EC2)
**Protocol:** Query/XML (like IAM/SNS/CloudFormation)
**Priority:** High

**Why it matters:**
EC2 is the foundational compute service in AWS — almost every AWS user interacts with it. Even though LocalStack's free tier only provides **mock CRUD** (no actual VMs), it's invaluable for testing infrastructure-as-code templates, validating API calls, and building CI/CD pipelines that reference EC2 resources.

**What LocalStack supports (free tier):**
- Instances: `RunInstances`, `DescribeInstances`, `StartInstances`, `StopInstances`, `TerminateInstances`
- Security Groups: `CreateSecurityGroup`, `DescribeSecurityGroups`, `AuthorizeSecurityGroupIngress/Egress`, `DeleteSecurityGroup`
- Key Pairs: `CreateKeyPair`, `DescribeKeyPairs`, `DeleteKeyPair`
- AMIs: `CreateImage`, `DescribeImages`, `DeregisterImage`
- VPCs / Subnets: basic CRUD (metadata only, not emulated)

**Limitation:** Instances are mocked — no actual VMs run. Display a prominent info banner.

**Suggested UI layout:** Tabbed HSplitView (Instances / Security Groups / Key Pairs tabs, like IAM). Instance list with state badges (pending / running / stopped / terminated). Security group detail with inbound/outbound rules table.

**Key features:**
- Instance list with ID, name tag, type, state badge, AZ, IPs
- Launch instance form (AMI, instance type, key pair, security group)
- Instance actions: Start, Stop, Terminate, Reboot
- Security group CRUD with inbound/outbound rule editor
- Key pair CRUD with private key download on creation
- Info banner: "EC2 instances are mocked — no actual VMs are created"

**Visual & Interaction Value:** ★★★★☆ (high — dashboard feel)
EC2 is the service that *looks* like infrastructure management. Even as mock CRUD, the UI is visually dense and interactive:
- **Multi-tab layout** (Instances / Security Groups / Key Pairs) — the most entity types in a single module after IAM, giving users a full "infrastructure console" feel
- **Instance state badges** with a 5-color state machine (pending=yellow, running=green, stopping=orange, stopped=red, terminated=gray) — the most intuitive status visualization since everyone understands "green = running"
- **Action buttons with state transitions**: Start grayed when running, Stop grayed when stopped, Terminate with confirmation dialog — the interplay between state and available actions makes the UI feel reactive and alive
- **Security group rules table** is a visually structured grid (Protocol | Port Range | Source/Dest | Description) with add/remove rows — gives a spreadsheet-like editing feel similar to DynamoDB's item grid
- **Inbound vs. Outbound tabs** within security group detail — a nested tab inside a tab, adding navigational depth
- **Key pair creation** is a one-shot interaction: create → immediately display private key → warn "this is the only time you can download it" — creates a memorable, high-stakes UI moment
- **Launch instance form** is the most complex create form in the app — AMI ID, instance type dropdown, key pair selector, security group selector, count — multi-field forms with cross-references between entities (key pairs and security groups created in other tabs)
- **IP address columns** (public + private) and **availability zone** give the instance list a network-infrastructure density that no other module has

---

## Phase 3 — EventBridge Scheduler: Timed Automation

**Service:** Amazon EventBridge Scheduler
**Protocol:** JSON 1.1, `X-Amz-Target: AWSScheduler.<Action>`, credential service: `scheduler`
**Priority:** Medium-High

**Why it matters:**
EventBridge Scheduler is the go-to service for time-based automation — cron jobs that invoke Lambda, send to SQS, trigger Step Functions, etc. It's a natural companion to our existing EventBridge module and could even live as a third tab alongside Buses and Rules. Developers use it constantly for delayed processing, periodic cleanup, and scheduled reports.

**What LocalStack supports (free tier):**
- `CreateSchedule`, `GetSchedule`, `UpdateSchedule`, `DeleteSchedule`, `ListSchedules`
- Schedule groups: `CreateScheduleGroup`, `ListScheduleGroups`, `DeleteScheduleGroup`
- Tag management: `TagResource`, `UntagResource`, `ListTagsForResource`

**Limitation:** Schedules are stored but **NOT executed** — no targets are invoked. Display a warning banner.

**Suggested UI layout:** Tab within the existing EventBridge module (Buses / Rules / Schedules), or standalone HSplitView — schedule list (left) → detail (right) with expression preview.

**Key features:**
- Schedule list with name, state badge (ENABLED / DISABLED), expression, target type
- Create schedule form: name, expression (cron/rate) with human-readable preview, target ARN, IAM role
- Enable/disable toggle
- Schedule groups CRUD
- Client-side "next occurrence" calculation from cron/rate expression
- Warning banner: "Schedules are stored but will NOT execute or trigger targets"

**Visual & Interaction Value:** ★★★☆☆ (medium — best as an extension, not standalone)
The real visual trick here is that this can **extend the existing EventBridge module** as a third tab (Buses / Rules / **Schedules**), which makes the EventBridge module feel like a fuller, more complete console without building an entirely new navigation entry:
- **Cron/rate expression preview** is the visual highlight — translating `cron(0 9 * * ? *)` into "Every day at 9:00 AM UTC" right below the input field gives immediate, satisfying feedback during schedule creation
- **"Next 5 occurrences" list** computed client-side from the expression — a small table showing upcoming fire times that makes abstract cron syntax tangible and verifiable
- **Target type badges** (Lambda / StepFunctions / SQS / SNS / ECS) — reuses the badge pattern but with service-specific icons/colors, visually linking schedules to the services they target
- **Enable/Disable toggle** is a single-click interaction that flips a state badge — simple but satisfying, and makes the list feel interactive even when schedules don't execute
- **Schedule groups** as a secondary organizer (collapsible sections or a group filter dropdown) adds a light layer of hierarchy
- Interaction is moderate — mostly CRUD with an enable/disable toggle. The visual payoff comes from the expression preview and next-occurrence calculation, not from deep drill-downs

---

## Phase 4 — Elasticsearch: Legacy Search Engine

**Service:** Amazon Elasticsearch Service (legacy)
**Protocol:** JSON 1.1 (management API) + REST (Elasticsearch engine)
**Priority:** Medium

**Why it matters:**
While AWS rebranded Elasticsearch Service to OpenSearch, many existing projects and tutorials still reference the Elasticsearch API. LocalStack runs **real single-node Elasticsearch clusters** in the free tier, and domains are shared between ES and OpenSearch services. Implementing this module provides coverage for teams that haven't migrated their terminology, and gives direct access to Elasticsearch-specific versioning.

**What LocalStack supports (free tier):**
- `CreateElasticsearchDomain`, `DescribeElasticsearchDomain(s)`, `ListDomainNames`, `DeleteElasticsearchDomain`, `UpdateElasticsearchDomainConfig`
- Real single-node Elasticsearch clusters with full REST API
- Domains are shared with OpenSearch Service (same underlying engine)

**Note:** Since OpenSearch is already implemented, this module can share significant code (service class patterns, domain models, XML/JSON parsers). The main difference is the API namespace and version naming.

**Suggested UI layout:** HSplitView — domain list (left) → domain detail (right) with endpoint, version badge, cluster health status. Similar to OpenSearch module.

**Key features:**
- Domain CRUD with Elasticsearch version selector
- Domain detail: endpoint URL (click-to-copy), version badge, cluster config
- Cluster health badge (green / yellow / red) via `_cluster/health`
- Index browser: list indices with doc count and size
- Note: "Domains are shared with OpenSearch Service"

**Visual & Interaction Value:** ★★★☆☆ (medium — fast to build, familiar patterns)
The biggest advantage here is **code reuse from the OpenSearch module** — the domain list, detail pane, endpoint display, and cluster health are nearly identical. The visual differentiation comes from version branding:
- **Cluster health traffic light** (green / yellow / red circle badge) is the most intuitive status indicator in any module — everyone understands traffic light colors instantly
- **Index browser** as a drill-down from domain detail adds a second navigation level — list indices with doc count, size, and a delete action. This is something the OpenSearch module already patterns, so it's low-effort high-reward
- **Version badge** distinguishing "Elasticsearch 7.10" vs "OpenSearch 2.x" helps users quickly identify which engine they're working with
- **Endpoint URL with click-to-copy** and an "Open in Browser" button — since the cluster is real, users can click through to the Elasticsearch REST API directly, making this one of the few modules that bridges to an external tool
- Interaction density is moderate — domain CRUD + index browsing. The visual appeal is in the health badges and the live cluster connection, not in complex forms or deep hierarchies
- **Fastest module to implement** due to OpenSearch code sharing — mostly renaming API targets and adjusting version labels

---

## Phase 5 — AWS Config: Resource Configuration Tracker

**Service:** AWS Config
**Protocol:** JSON 1.1, `X-Amz-Target: StarlingDoveService.<Action>`
**Priority:** Medium-Low

**Why it matters:**
AWS Config is the auditing backbone for compliance-conscious teams — it records resource configurations over time and evaluates them against rules. While LocalStack's free tier only provides **mock CRUD** (recorders don't actually capture changes), it's useful for testing IaC templates that set up Config recorders and delivery channels, and for validating API interactions in CI pipelines.

**What LocalStack supports (free tier):**
- Configuration Recorders: `PutConfigurationRecorder`, `DescribeConfigurationRecorders`, `DescribeConfigurationRecorderStatus`, `StartConfigurationRecorder`, `StopConfigurationRecorder`, `DeleteConfigurationRecorder`
- Delivery Channels: `PutDeliveryChannel`, `DescribeDeliveryChannels`, `DeleteDeliveryChannel`
- Persistence supported (configurations survive restarts)

**Limitation:** Recorders can be managed but do **NOT** actually record resource changes. No compliance rule evaluation.

**Suggested UI layout:** Single-pane or simple HSplitView — two sections (Configuration Recorders + Delivery Channels), similar to Route 53 Resolver's sectioned list.

**Key features:**
- Configuration recorder CRUD with status badges (RECORDING / STOPPED)
- Start/Stop recorder toggle
- Delivery channel CRUD (S3 bucket, SNS topic, frequency)
- Combined status view showing recorder + channel state
- Warning banner: "Config recorders are mocked — resource changes are NOT recorded"

**Visual & Interaction Value:** ★★☆☆☆ (low — utility panel, not a visual showcase)
This is a configuration-management module with a small, static surface. The visual interest is limited but there are a few useful tricks:
- **Recording status as an animated/pulsing badge** — a green "RECORDING" badge vs. a gray "STOPPED" badge, with a Start/Stop toggle that flips between them. It's the entire interaction loop in one click
- **Two-section layout** (Recorders + Delivery Channels) in a single pane — similar to how STS shows caller identity + assume role in one view. No split view needed, which makes it the lightest layout in the app
- **Delivery channel configuration** shows the S3 bucket → SNS topic pipeline as a simple "from → to" display, giving a hint of flow visualization without building actual diagrams
- Interaction is minimal — CRUD for recorders and channels, plus a start/stop toggle. No drill-downs, no nested data, no lists that grow over time. This is a "set it and check it" module
- **Best suited as a quick implementation** between more complex phases — it's a palate cleanser, not a showpiece

---

## Phase 6 — Resource Groups: Tag-Based Organization

**Service:** Amazon Resource Groups & Tagging API
**Protocol:** JSON 1.1
**Priority:** Low

**Why it matters:**
Resource Groups lets users organize AWS resources by tags or CloudFormation stacks — useful for bulk operations and cost visibility. It's a lightweight utility service. The value in a LocalStack GUI is limited since most users work with individual services, but it provides completeness for teams testing tag-based automation or resource organization workflows.

**What LocalStack supports (free tier):**
- `CreateGroup`, `UpdateGroup`, `UpdateGroupQuery`, `DeleteGroup`, `ListGroups`, `GetGroup`, `GetGroupQuery`
- Tag-based queries (`TAG_FILTERS_1_0`)
- Resource Groups Tagging API for cross-service tag operations

**Suggested UI layout:** HSplitView — group list (left) → group detail with query viewer and matched resources (right). Simple and compact.

**Key features:**
- Resource group CRUD
- Tag filter builder (key-value pairs)
- Group detail: query viewer, resource type filter
- Matched resources list (ARN, type badge, tags)

**Visual & Interaction Value:** ★★☆☆☆ (low — organizational utility, limited visual payoff)
Resource Groups is fundamentally a **meta-service** — it organizes other services' resources rather than managing its own. The visual surface is thin:
- **Tag filter builder** is the most interactive element — a dynamic form where users add key-value pair rows with +/- buttons, similar to DynamoDB's put-item form or Lambda's env vars editor. This is familiar to build but doesn't break new ground
- **Matched resources list** with **service type badges** (S3 / Lambda / DynamoDB / EC2 / etc.) is the one visually interesting element — a heterogeneous list where each row has a different color badge based on the AWS service it belongs to. This cross-service view is unique in the app
- **Query viewer** displaying the group's filter JSON — a read-only code block, similar to policy viewers in IAM
- Interaction is shallow: create group → see matched resources. No state changes, no actions on matched resources, no drill-downs beyond the initial list
- **Best case scenario**: this becomes a "resource explorer" that gives users a cross-cutting view of their LocalStack environment. Worst case: it's a CRUD list with a JSON viewer

---

## Phase 7 — Transcribe: Speech-to-Text Jobs

**Service:** Amazon Transcribe
**Protocol:** JSON 1.1, `X-Amz-Target: Transcribe.<Action>`
**Priority:** Low

**Why it matters:**
Transcribe converts audio files to text using the Vosk offline speech-to-text engine. It's a niche but **actually functional** service in LocalStack's free tier — transcription jobs really execute and produce output. Useful for teams building voice-powered applications, call center analytics, or subtitle generation workflows locally.

**What LocalStack supports (free tier):**
- `StartTranscriptionJob`, `ListTranscriptionJobs`, `GetTranscriptionJob`, `DeleteTranscriptionJob`
- Real transcription via Vosk offline engine (25+ languages)
- 7+ audio formats (WAV, MP3, FLAC, etc.)
- Output saved to S3 buckets
- Requires initial internet access to download language models (~50 MB each)

**Suggested UI layout:** HSplitView — job list (left) → job detail with transcript viewer (right). Status badges (QUEUED / IN_PROGRESS / COMPLETED / FAILED).

**Key features:**
- Transcription job list with status badges and language
- Create job form: name, S3 media URI, language selector (25+ languages), output bucket
- Job detail: status, input/output URIs (click-to-copy), error message for failures
- Transcript preview pane with formatted text
- Delete job

**Visual & Interaction Value:** ★★★☆☆ (medium — async job pattern with a unique output type)
Transcribe is niche, but it introduces a UI pattern we don't have anywhere else — **async job monitoring with rich text output**:
- **Job status progression** (QUEUED → IN_PROGRESS → COMPLETED/FAILED) is a natural fit for **polling with auto-refresh** — users submit a job and watch the status badge change over time. This is the only module with a meaningful "waiting" state where the user benefits from staying on the page
- **Transcript preview pane** is the unique visual element — a large, scrollable text area showing the transcribed output. No other module displays free-form natural language text as its primary output. This breaks the pattern of JSON/table/badge displays
- **Language selector dropdown** with 25+ languages (en-US, es-ES, fr-FR, de-DE, ja-JP, zh-CN, etc.) is the largest dropdown in the app — gives an international/polished feel
- **Audio format badges** (WAV / MP3 / FLAC / OGG / etc.) on the job list add visual variety
- **S3 URI inputs** for both source and destination — these could link to the S3 module (click to navigate to the bucket), creating cross-module navigation that no other module offers
- Interaction is a **submit-and-wait loop**: create job → watch progress → read output. Lower interaction density than Step Functions but higher visual payoff than Config or Resource Groups because the output (human-readable text) is inherently more interesting to look at than JSON

---

## Phase 8 (Skipped) — AWS Support API

**Service:** AWS Support
**Priority:** Lowest (optional)

**Why it matters (barely):**
The Support API in LocalStack is a bare-minimum mock — it can create, list, and resolve support cases, but nothing functional happens. The UI surface is extremely limited (basically a ticket list). Only implement if aiming for 100% free-tier coverage.

**What LocalStack supports:** `CreateCase`, `DescribeCases`, `ResolveCase` (all mocked, no actual support interaction).

**Visual & Interaction Value:** ★☆☆☆☆ (minimal)
A flat ticket list with subject, status (OPENED/RESOLVED), and a resolve button. No drill-downs, no rich data, no badges beyond open/closed. Visually indistinguishable from a to-do list. Only implement for completeness.

---

## Summary

| Phase | Service | Functional? | Visual/Interaction | Complexity | Value |
|-------|---------|-------------|--------------------|------------|-------|
| 1 | Step Functions | Full execution | ★★★★★ 3-level drill-down, live execution, dual JSON viewers, 8 state-type badges | High | Highest |
| 2 | EC2 | Mock CRUD only | ★★★★☆ Multi-tab dashboard, state machine UX, security rules grid, complex forms | High | High |
| 3 | EventBridge Scheduler | Mock (no exec) | ★★★☆☆ Cron preview, next-occurrence calc, extends existing module | Medium | Medium-High |
| 4 | Elasticsearch | Real clusters | ★★★☆☆ Health traffic light, index browser, fast build via OpenSearch reuse | Medium | Medium |
| 5 | AWS Config | Mock CRUD only | ★★☆☆☆ Start/stop toggle, two-section layout, lightweight | Low | Medium-Low |
| 6 | Resource Groups | Tag queries work | ★★☆☆☆ Cross-service badge list, tag filter builder | Low | Low |
| 7 | Transcribe | Real transcription | ★★★☆☆ Async job polling, transcript text output, language selector | Medium | Low |
| 8 | Support API | Mock only | ★☆☆☆☆ Flat ticket list, open/closed only | Low | Lowest |
