# Favorite Regions Rollout Plan

## Status
- Shared infrastructure: COMPLETE
- SQS (reference implementation): COMPLETE
- Standard services (20): COMPLETE
- Complex services (2): DEFERRED (EC2 multi-entity, CloudWatch Metrics grouped/single-select)

## Shared Components (in Navigation/)
All already implemented and working:
- `FavoriteRegionStore` — persists favorites per connection profile
- `FavoriteRegionLoader<Item>` — generic per-region state + `switchRegion(to:...)` helper
- `FavoriteRegionSections<Item, RowContent>` — expandable list sections with tap-to-switch
- `AddFavoriteRegionButton` — sheet UI to add/remove favorites
- `.favoriteRegionSupport(regionLoader:load:)` — modifier bundling sync + connection-reset

## Per-Service Additions (~12 lines each)

All boilerplate is absorbed by the shared components. Each view only adds:

```swift
// 1. State (1 line)
@StateObject private var regionLoader = FavoriteRegionLoader<YourModel>()

// 2. In body VStack, after list content (1 line)
AddFavoriteRegionButton(currentRegion: appState.region)

// 3. In List, after main ForEach (3 lines)
FavoriteRegionSections(loader: regionLoader, currentRegion: appState.region,
    selectBy: \.name
) { item in /* row content */ }

// 4. Modifier on the view (1 line)
.favoriteRegionSupport(regionLoader: regionLoader) { [service] in try await service.listWhatever(region: $0) }

// 5. In .onAutoRefresh block (1 line)
regionLoader.loadAllExpanded(silent: true)

// 6. In load function, after items loaded (3 lines)
if let item = regionLoader.consumePendingSelection(from: items, by: \.name) {
    selectedIDs = [item.id]
    activeItem = item
}

// 7. Show List even when items are empty (so favorites are visible)
// Move EmptyStateView inside List, use ForEach instead of List(items)
```

## Services to Add (21 regional)

### Messaging & Integration
- [x] SNS — `SNSTopicListView`, model: `SNSTopic`, load: `service.listTopics(region:)`, select by: `topicArn`
- [x] SES — `SESIdentityListView`, model: `SESIdentity`, load: `service.listIdentities(region:)`, select by: `identity`
- [x] EventBridge — `EventBridgeBusListView`, model: `EventBridgeBus`, load: `service.listEventBuses(region:)`, select by: `name`
- [x] Kinesis — `KinesisStreamListView`, model: `KinesisStreamSummary`, load: `service.listStreams(region:)`, select by: `streamName`

### Compute
- [x] Lambda — `LambdaFunctionListView`, model: `LambdaFunction`, load: `service.listFunctions(region:)`, select by: `functionName`
- [x] Step Functions — `StepFunctionsStateMachineListView`, model: `StateMachineSummary`, load: `service.listStateMachines(region:)`, select by: `name`
- [ ] EC2 — DEFERRED: multi-entity (instances/SGs/key pairs), needs 3 loaders or custom approach, `listSecurityGroups`/`listKeyPairs` missing `region:` param

### Storage & Database
- [x] DynamoDB — `DynamoDBTableListView`, model: `DynamoDBTable`, load: `service.listTables(region:)`, select by: `tableName`
- [x] Redshift — `RedshiftClusterListView`, model: `RedshiftCluster`, load: `service.describeClusters(region:)`, select by: `clusterIdentifier`
- [x] OpenSearch — `OpenSearchDomainListView`, model: `OpenSearchDomain`, load: `service.listDomains(region:)`, select by: `domainName`

### Security & Identity
- [x] Secrets Manager — `SecretsListView`, model: `Secret`, load: `service.listSecrets(region:)`, select by: `name`
- [x] KMS — `KMSKeyListView`, model: `KMSKey`, load: `service.listKeys(region:)`, select by: `keyId`
- [x] ACM — `ACMCertificateListView`, model: `ACMCertificateSummary`, load: `service.listCertificates(region:)`, select by: `certificateArn`

### Management & Governance
- [x] SSM — `SSMParameterListView`, model: `SSMParameter`, load: `service.describeParameters(region:)`, select by: `name`
- [x] CloudWatch Logs — `CloudWatchLogsGroupListView`, model: `CloudWatchLogGroup`, load: `service.describeLogGroups(region:)`, select by: `logGroupName`
- [x] CloudWatch Alarms — `CloudWatchAlarmListView`, model: `CloudWatchAlarm`, load: `service.describeAlarms(region:)`, select by: `alarmName`
- [ ] CloudWatch Metrics — DEFERRED: single-select with namespace grouping via DisclosureGroup, fundamentally different list pattern
- [x] CloudFormation — `CloudFormationStackListView`, model: `CloudFormationStack`, load: `service.listStacks(region:)`, select by: `stackName`
- [x] Config — `ConfigRecorderListView`, model: `ConfigurationRecorder`, load: `service.describeConfigurationRecorders(region:)`, select by: `name`
- [x] Resource Groups — `ResourceGroupsListView`, model: `ResourceGroupSummary`, load: `service.listGroups(region:)`, select by: `name`
- [x] Transcribe — `TranscribeJobListView`, model: `TranscriptionJob`, load: `service.listTranscriptionJobs(region:)`, select by: `jobName`

### Networking
- [x] API Gateway — `APIGatewayAPIListView`, model: `RestApi`, load: `service.listRestApis(region:)`, select by: `name`

## Services That Skip Favorites (5 global)
- S3 (global on LocalStack)
- IAM (global)
- Route 53 (global)
- STS (global)
- Support (hardcoded us-east-1)

## Reference Implementation
See `SQSQueueListView.swift` for the complete working example.
