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
Sources/LocalStackNavigator/
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
- `Modules/LocalStackModule.swift` — Protocol all service modules conform to
- `Safety/SafetyGuard.swift` — Validates endpoints are local
- `Networking/LocalStackClient.swift` — Async HTTP client with read-only guard

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
```
