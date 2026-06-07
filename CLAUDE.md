# Local Cloud Browser — Project Guide

## Overview
Native macOS SwiftUI application for managing AWS-compatible endpoints. Provides a GUI for browsing and interacting with cloud services (S3, SQS, SNS, Secrets Manager).

## Tech Stack
- **Language:** Swift 6.0
- **UI:** SwiftUI, macOS 14+
- **Build:** Xcode project (`Local Cloud Browser.xcodeproj`) using PBXFileSystemSynchronizedRootGroup — files auto-discovered, no manual target membership
- **Architecture:** Module-based with enum-driven routing

## Project Structure
```
LocalCloudBrowser/
├── App/           — Entry point, global state, command menus
├── Navigation/    — Sidebar, content shell, route enum
├── Modules/       — Service modules (protocol + per-service views) + Donation panel
├── Safety/        — Endpoint validation, read-only interceptor
├── Networking/    — HTTP client + SigV4 signing
└── Settings/      — Connection configuration model
```

## Key Files
- `App/AppState.swift` — Global ObservableObject; holds connection state, endpoint, read-only flag, selected route
- `App/HelpCommands.swift` — All `Commands` for the menu bar (File, Connection, Donation, Help) + FocusedValueKeys
- `Navigation/Route.swift` — Enum of all navigable services
- `Navigation/ContentView.swift` — Main NavigationSplitView shell; owns the donation sheet binding and the floating heart overlay
- `Modules/ServiceModule.swift` — Protocol all service modules conform to
- `Modules/Donation/` — Donation panel: addresses, runtime QR generator, modal view, bottom-trailing heart button
- `Safety/SafetyGuard.swift` — Validates endpoints are local
- `Networking/CloudClient.swift` — Async HTTP client with read-only guard
- `Networking/SigV4Signer.swift` — AWS SigV4 request signing (used for non-local endpoints)

## Conventions
- All UI state flows through `AppState` via `@EnvironmentObject`
- New services: add a case to `Route`, create a `Modules/<Service>/` directory with a view, wire it in `ContentView.detailView(for:)`
- Read-only mode defaults to **on** — mutating HTTP methods are blocked unless toggled off
- Endpoint safety: non-local endpoints show a warning banner in the sidebar
- Swift concurrency: use `@MainActor` for UI-bound classes

## Build & Run
```bash
xcodebuild -project "Local Cloud Browser.xcodeproj" -scheme LocalCloudBrowser -configuration Debug build
# or open in Xcode and ⌘R
```

## Distribution

Shipped outside the App Store as a signed + notarized DMG. App Store is **not** the target — no IAP, no per-feature paywalls; the app is free with full features.

- **Signing identity:** `Developer ID Application: Milan Karakaya (MQXW376WC6)` (in login keychain)
- **Notarization profile:** `notarytool` (`xcrun notarytool` keychain profile in login keychain)
- **Release flow:**
  1. Archive in Xcode → Organizer → Distribute App → Direct Distribution (produces a notarized + stapled `.app`)
  2. Stage `.app` + Applications symlink into a folder, then `hdiutil create -volname "Local Cloud Browser" -srcfolder <stage> -format UDZO <name>.dmg`
  3. `codesign --sign "Developer ID Application: Milan Karakaya (MQXW376WC6)" --options runtime --timestamp <dmg>`
  4. `xcrun notarytool submit <dmg> --keychain-profile notarytool --wait`
  5. `xcrun stapler staple <dmg>`
  6. `spctl --assess --type open --context context:primary-signature -v <dmg>` should print `accepted, source=Notarized Developer ID`
  7. `gh release upload release <dmg> --clobber --repo milan0x/local-cloud-browser`
- Both the `.app` and the `.dmg` are notarized and stapled, so download → mount → open → run is warning-free even offline.

## Build & Test Rules

### After Every Code Change
- Run the xcodebuild command above after modifying any file under `LocalCloudBrowser/`. Always rebuild so the binary stays current.
- If the build fails, fix compilation errors before moving on.
- SourceKit LSP diagnostics are noise — verify with actual `xcodebuild`.

### After Completing a Task
- A test scheme is not yet wired into the Xcode project (tests live under `Tests/` but cannot be run via `xcodebuild test` until a test target is added). Skip the run-tests step until the scheme is fixed.
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

## Design Context

### Users
Individual developers and small DevOps/platform teams who manage local AWS-compatible services (LocalStack, MinIO) during development. They use the app as a daily companion while building and debugging — it needs to stay out of the way and just work.

### Brand Personality
**Professional, clear, reliable.** Quiet confidence, zero theatrics. Clarity of information, predictable behavior, and consistency above all. Friendly without being playful, capable without being showy.

### Aesthetic Direction
- **Visual tone**: Native macOS, utilitarian, polished but restrained
- **References**: Proxyman, TablePlus, Xcode, Instruments
- **Anti-references**: Electron apps, AWS Console density, generic SaaS dashboards
- **Theme**: System appearance (light + dark via semantic SwiftUI colors)
- **Typography**: System fonts only (SF Pro, SF Mono)
- **Iconography**: SF Symbols exclusively

### Design Principles
1. **Clarity over cleverness**: Communicate, don't decorate. No fancy UI/UX tricks.
2. **Native and invisible**: Follow macOS HIG faithfully. Feel like it ships with the OS.
3. **Safety by default**: Read-only on, endpoint validation, confirmation for destructive actions.
4. **Consistency across modules**: All service modules feel identical via shared components.
5. **Information density, not overload**: Progressive disclosure to layer information.
