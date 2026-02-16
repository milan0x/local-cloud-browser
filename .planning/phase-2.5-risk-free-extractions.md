# Phase 2.5: Risk-Free Extractions (~644 lines)

Three verbatim-identical patterns to extract. Same mechanical approach as Phase 1.

---

## 2.5A. ConnectionLostBanner → `Navigation/ConnectionLostBanner.swift`

**28 files** have this identical computed property:

```swift
private var connectionLostBanner: some View {
    HStack(spacing: 6) {
        Image(systemName: "bolt.horizontal.circle")
            .font(.caption)
        Text("Connection lost — showing cached data")
            .font(.caption)
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .frame(maxWidth: .infinity)
    .background(.orange.gradient, in: RoundedRectangle(cornerRadius: 6))
    .padding(6)
}
```

**Create** a shared `ConnectionLostBanner` view (simple struct, no parameters).
**Replace** all 28 `private var connectionLostBanner` computed properties with usage of the shared view.
Each call site uses it as: `.overlay(alignment: .bottom) { if errorMessage != nil { connectionLostBanner } }`
After extraction: `.overlay(alignment: .bottom) { if errorMessage != nil { ConnectionLostBanner() } }`

**Files (28):**
- SQS/SQSQueueListView.swift
- SNS/SNSTopicListView.swift
- SES/SESIdentityListView.swift
- DynamoDB/DynamoDBTableListView.swift
- DynamoDB/DynamoDBItemBrowserView.swift
- SecretsManager/SecretsListView.swift
- SSM/SSMParameterListView.swift
- Lambda/LambdaFunctionListView.swift
- CloudWatchLogs/CloudWatchLogsGroupListView.swift
- CloudWatch/CloudWatchAlarmListView.swift
- CloudWatch/CloudWatchMetricListView.swift (check — may not have one)
- EventBridge/EventBridgeBusListView.swift
- EventBridge/EventBridgeScheduleGroupListView.swift
- CloudFormation/CloudFormationStackListView.swift
- APIGateway/APIGatewayAPIListView.swift
- ACM/ACMCertificateListView.swift
- Kinesis/KinesisStreamListView.swift
- Kinesis/KinesisFirehoseListView.swift
- KMS/KMSKeyListView.swift
- Route53/Route53ZoneListView.swift
- Route53/Route53ResolverListView.swift
- Redshift/RedshiftClusterListView.swift
- OpenSearch/OpenSearchDomainListView.swift
- StepFunctions/StepFunctionsStateMachineListView.swift
- EC2/EC2EntityListView.swift (check — may use different pattern)
- Config/ConfigRecorderListView.swift
- Config/ConfigDeliveryChannelListView.swift
- Transcribe/TranscribeJobListView.swift
- Support/SupportCaseListView.swift
- ResourceGroups/ResourceGroupsListView.swift
- S3/S3BucketListView.swift

Grep to find exact list: `private var connectionLostBanner: some View`

---

## 2.5B. ConnectionRetryingLabel — inline extraction inside loading states

**28 files** have this identical block inside their loading state:

```swift
if appState.connectionError != nil {
    Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

This appears inside a `VStack(spacing: 12) { ProgressView("Loading ...") ... }` block.

**Create** a shared `ConnectionRetryingLabel` view in the same file as ConnectionLostBanner (or its own file).
**Replace** all 28 inline blocks with `ConnectionRetryingLabel()`.

The label needs `@EnvironmentObject var appState: AppState` to check `appState.connectionError != nil`, OR the caller keeps the `if` check and the shared view is just the Label. Simpler approach: keep the `if` at the call site, extract only the Label+modifiers:

```swift
struct ConnectionRetryingLabel: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        if appState.connectionError != nil {
            Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
```

Then replace: `if appState.connectionError != nil { Label(...) }` → `ConnectionRetryingLabel()`

Grep to find exact list: `Label("Connection lost — retrying...", systemImage: "bolt.horizontal.circle")`

---

## 2.5C. SyncSelectionModifier → `Navigation/SyncSelectionModifier.swift`

**32 files** have this identical `.onChange` pattern:

```swift
.onChange(of: selectedXxxIDs) {
    if selectedXxxIDs.count == 1, let id = selectedXxxIDs.first {
        activeXxx = items.first { $0.id == id }
    } else {
        activeXxx = nil
    }
}
```

Variable names differ but the structure is identical. Extract as a ViewModifier that takes bindings:

```swift
struct SyncSelectionModifier<Item: Identifiable>: ViewModifier {
    let selectedIDs: Set<Item.ID>
    let items: [Item]
    @Binding var activeItem: Item?

    func body(content: Content) -> some View {
        content
            .onChange(of: selectedIDs) {
                if selectedIDs.count == 1, let id = selectedIDs.first {
                    activeItem = items.first { $0.id == id }
                } else {
                    activeItem = nil
                }
            }
    }
}

extension View {
    func syncSelection<Item: Identifiable>(
        _ selectedIDs: Set<Item.ID>,
        items: [Item],
        activeItem: Binding<Item?>
    ) -> some View {
        modifier(SyncSelectionModifier(selectedIDs: selectedIDs, items: items, activeItem: activeItem))
    }
}
```

**Replacement pattern:**
Before: `.onChange(of: selectedQueueIDs) { if selectedQueueIDs.count == 1 ... }`
After: `.syncSelection(selectedQueueIDs, items: queues, activeItem: $activeQueue)`

NOTE: Item.ID must be Hashable (it already is since Set<Item.ID> requires it). Some files may have slight variations (e.g., EC2EntityListView has a different selection pattern with tabs) — skip those and only replace the standard pattern.

Grep to find candidates: `.onChange(of: selected` followed by `count == 1`

**Files (32):** Use grep `.onChange(of: selected\w+IDs) {` to get the full list. Verify each has the standard pattern before replacing.

---

## Execution Steps

1. Create `Navigation/ConnectionLostBanner.swift` with both `ConnectionLostBanner` and `ConnectionRetryingLabel` → `swift build`
2. Create `Navigation/SyncSelectionModifier.swift` → `swift build`
3. **Wave 1** (files 1-15): Replace all 3 patterns → `swift build`
4. **Wave 2** (files 16-32): Replace all 3 patterns → `swift build`
5. `swift test` — all tests must pass
6. Update `.planning/deduplication-plan.md` — mark 2.5 complete
7. Commit

## Expected Impact
- ~644 lines saved
- 3 new shared components
- ~32 files changed
