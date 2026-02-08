# LocalStack Navigator — Design Document

## Vision
A native macOS application that provides a graphical interface for managing LocalStack AWS environments. The app prioritizes safety (preventing accidental operations on real AWS), discoverability, and a native macOS experience.

## Core Principles
1. **Safety First** — Default to read-only mode; validate endpoints are local; warn on non-local connections
2. **Native Experience** — SwiftUI with NavigationSplitView; follows macOS HIG
3. **Modular Architecture** — Each AWS service is an independent module conforming to a shared protocol
4. **Progressive Disclosure** — Start simple, reveal complexity as needed

## Architecture

### Module Protocol
```swift
protocol LocalStackModule {
    var serviceName: String { get }
    var serviceIcon: String { get }
    var serviceEndpoint: String { get }
    func makeMainView() -> AnyView
    func makeSidebarDetail() -> AnyView?
}
```

### Navigation
- Enum-driven routing via `Route` (CaseIterable)
- NavigationSplitView with sidebar + detail pane
- Sidebar shows all available services with icons

### Safety Layer
- `SafetyGuard` validates endpoints against localhost/127.0.0.1/.local
- `ReadOnlyInterceptor` blocks mutating HTTP methods when read-only is enabled
- Visual indicators: connection status dot, non-local warning banner, lock icon for read-only

### Networking
- `LocalStackClient` wraps URLSession with async/await
- Configurable base URL from AppState
- All requests pass through read-only check

## Supported Services (Phase 1)
- **S3** — Bucket browsing, object management
- **SQS** — Queue management, message send/receive
- **SNS** — Topic and subscription management
- **Secrets Manager** — Secret storage and retrieval

## Future Services
- Lambda, DynamoDB, CloudFormation, IAM, CloudWatch, API Gateway

## Phased Rollout
1. **Phase 1:** Shell + Sidebar + Router + Module Protocol + Stubs
2. **Phase 2:** S3 module (full implementation)
3. **Phase 3:** SQS module
4. **Phase 4:** SNS module
5. **Phase 5:** Secrets Manager module
6. **Phase 6:** Settings UI, persistence, polish
