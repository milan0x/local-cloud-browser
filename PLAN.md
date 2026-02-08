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
- [ ] Settings UI (endpoint, region, credentials)
- [ ] Persist settings to UserDefaults or file
- [ ] Connection health check (ping LocalStack)
- [ ] Error handling improvements
- [ ] Keyboard shortcuts
- [ ] Menu bar integration
