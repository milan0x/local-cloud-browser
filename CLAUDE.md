# LocalStack Navigator — Project Guide

## Overview
Native macOS SwiftUI application for managing LocalStack AWS environments. Provides a GUI for browsing and interacting with LocalStack services (S3, SQS, SNS, Secrets Manager).

## Tech Stack
- **Language:** Swift 6.0
- **UI:** SwiftUI, macOS 14+
- **Package Manager:** Swift Package Manager (Package.swift)
- **Architecture:** Module-based with enum-driven routing

## Project Structure
```
Sources/LocalCloudBrowser/
├── App/           — Entry point and global state
├── Navigation/    — Sidebar, content shell, route enum
├── Modules/       — Service modules (protocol + per-service views)
├── Safety/        — Endpoint validation, read-only interceptor
├── Networking/    — HTTP client for LocalStack API
└── Settings/      — Connection configuration model
```

## Key Files
- `App/AppState.swift` — Global ObservableObject; holds connection state, endpoint, read-only flag, selected route
- `Navigation/Route.swift` — Enum of all navigable services
- `Navigation/ContentView.swift` — Main NavigationSplitView shell
- `Modules/ServiceModule.swift` — Protocol all service modules conform to
- `Safety/SafetyGuard.swift` — Validates endpoints are local
- `Networking/CloudClient.swift` — Async HTTP client with read-only guard

## Conventions
- All UI state flows through `AppState` via `@EnvironmentObject`
- New services: add a case to `Route`, create a `Modules/<Service>/` directory with a view, wire it in `ContentView.detailView(for:)`
- Read-only mode defaults to **on** — mutating HTTP methods are blocked unless toggled off
- Endpoint safety: non-local endpoints show a warning banner in the sidebar
- Swift concurrency: use `@MainActor` for UI-bound classes

## Build & Run
```bash
swift build        # Build from CLI
swift run          # Run from CLI (or open Package.swift in Xcode and Cmd+R)
swift test         # Run unit tests
```

## Build & Test Rules

### After Every Code Change
- Run `swift build` after modifying any file under `Sources/`. The project compiles in ~2 seconds — always rebuild so the binary stays current.
- If the build fails, fix compilation errors before moving on.

### After Completing a Task
- Run `swift test` and ensure all tests pass.
- If tests fail, fix the code to make them pass. Do NOT modify or delete tests to make them pass unless the test itself is wrong.
- Do NOT write new tests unless explicitly asked to.

### What Is Testable (Unit Tests Only)
Tests cover **pure logic only** — code that takes input and returns output with no UI dependency:
- Parsers: `SNSXMLParser`, `S3XMLParser`, `ServiceError.parse`, `JSONHelperParser`
- Model computed properties: `SQSMessage.bodyType`, `.truncatedId`, `S3Object.isFolder`, etc.
- CLI helpers: `.toAWSCLI()`, `.sendMessageCLI()`, shell escaping
- Safety: `SafetyGuard.evaluate()`, `ReadOnlyInterceptor.allowsRequest()`
- Codable models: encode/decode round-trips
- Static utility functions: URL rewriting, form encoding, region validation

### What Is NOT Testable (Never Write Tests For These)
- SwiftUI views (`View`, `body`, modifiers, sheets, alerts, toolbars)
- `@StateObject`, `@EnvironmentObject`, `@State`, `@Binding`
- `ObservableObject` classes that depend on `AppState` or UI lifecycle
- Anything requiring a running app, window server, or user interaction
- `NSViewRepresentable` wrappers (`CodeTextEditor`, `PaneClickDetector`, etc.)
