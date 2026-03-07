# Monetization Implementation Plan

## Overview
Free tier with read-only access. One-time IAP to unlock full write access permanently. No custom trial — fully App Store compliant.

## Pricing Model Summary

| Tier | Access |
|------|--------|
| Free | Read-only — browse, inspect, and view all 28 AWS services |
| Paid (Pro) | Full access — create, modify, delete resources with no restrictions |

---

## Implementation Steps

### Step 1: LicenseManager

**File:** `Sources/LocalCloudBrowser/App/LicenseManager.swift`

`@MainActor` `ObservableObject` — single source of truth for license state.

```
enum LicenseState {
    case free
    case paid
}
```

**Responsibilities:**
- On init, check StoreKit purchase status
- Expose `isPaid: Bool` backed by StoreKit 2 entitlement check
- Expose `canWrite: Bool` — returns `true` only if `.paid`
- In `.free` mode, force `appState.isReadOnly = true`
- On purchase, transition to `.paid` and unlock read-only

**No UserDefaults tracking** — all state derived from StoreKit entitlements.

### Step 2: StoreKit 2 Integration

**File:** `Sources/LocalCloudBrowser/App/StoreKitManager.swift`

**Product setup:**
- One non-consumable IAP: product ID `com.localcloudbrowser.pro`
- StoreKit 2 (`Product`, `Transaction`) — modern async API

**Responsibilities:**
- `loadProduct()` — fetch the product from App Store
- `purchase()` — initiate purchase flow
- `restorePurchases()` — call `Transaction.currentEntitlements`
- `isPurchased: Bool` — check entitlement status
- Listen for `Transaction.updates` on app launch

### Step 3: Wire LicenseManager into the App

**File:** `Sources/LocalCloudBrowser/App/LocalCloudBrowserApp.swift`

- `LicenseManager` and `StoreKitManager` as `@StateObject`
- Injected as `.environmentObject` on all view hierarchies

### Step 4: Gate Write Actions

**Approach:** LicenseManager forces `appState.isReadOnly = true` in free mode. The existing `ReadOnlyInterceptor` blocks writes automatically — no interceptor changes needed.

### Step 5: Lock the Read-Only Toggle in Free Mode

**File:** `Sources/LocalCloudBrowser/Navigation/SidebarView.swift`

- If `.free`: tapping lock opens upgrade sheet instead of toggling
- If `.paid`: current behavior unchanged

### Step 6: Free Badge

**File:** `Sources/LocalCloudBrowser/Navigation/ContentView.swift`

- Dark red badge overlay pinned to bottom-right corner
- Shows "Free — Read Only" in free mode, hidden when paid
- Clickable — opens upgrade sheet

### Step 7: Upgrade Modal

**File:** `Sources/LocalCloudBrowser/App/UpgradeView.swift`

- Sleek native macOS sheet with purchase, restore, and dismiss buttons
- One-time purchase messaging — "Pay once, own it forever"

### Step 8: Settings Integration

**File:** `Sources/LocalCloudBrowser/App/SettingsView.swift`

- License tab shows "Free" (orange) or "Pro" (green)
- Purchase and restore buttons when not paid

### Step 9: App Store Sandbox Compliance

**Files created:**
- `LocalCloudBrowser.entitlements` — App Sandbox with network client and user-selected file access
- `Info.plist` — ATS exceptions for `localhost.localstack.cloud` subdomains, local networking enabled

---

## Files Summary

### Files:
| File | Purpose |
|------|---------|
| `App/LicenseManager.swift` | License state machine (free/paid), StoreKit-backed |
| `App/StoreKitManager.swift` | StoreKit 2 product loading, purchase, restore, transaction listener |
| `App/UpgradeView.swift` | Purchase modal sheet |
| `LocalCloudBrowser.entitlements` | App Sandbox entitlements for App Store |
| `Info.plist` | ATS exceptions for LocalStack HTTP domains |
| `Tests/LicenseManagerTests.swift` | Tests for LicenseState |

### Modified files:
| File | Change |
|------|--------|
| `App/LocalCloudBrowserApp.swift` | Create and inject LicenseManager + StoreKitManager |
| `App/SettingsView.swift` | License tab with status, purchase, and restore |
| `App/HelpCommands.swift` | "Upgrade to Pro" and "Restore Purchase" menu items |
| `Navigation/ContentView.swift` | Free badge overlay, upgrade sheet |
| `Navigation/SidebarView.swift` | Read-only toggle locks in free mode, triggers upgrade sheet |

### Unchanged:
| File | Why |
|------|-----|
| `Safety/ReadOnlyInterceptor.swift` | Free mode forces `appState.isReadOnly = true` — interceptor works as-is |
| `Networking/CloudClient.swift` | Already checks `isReadOnly` via the interceptor |
| All 28 module views | They already respect `isReadOnly` — no per-module changes needed |

---

## App Store Requirements Checklist

- [ ] Non-consumable IAP registered in App Store Connect (`com.localcloudbrowser.pro`)
- [ ] Create `.storekit` configuration file for Xcode testing
- [ ] App Review notes explaining the free/paid model
- [ ] Privacy policy (required for paid apps)
- [x] App sandbox entitlements (`LocalCloudBrowser.entitlements`)
- [x] ATS exceptions for LocalStack HTTP domains (`Info.plist`)
- [ ] Signing with Developer ID / Mac App Store certificate
- [x] Restore Purchase accessible without paywall (App Store Review Guideline 3.1.1)

---

## Testing

### Unit tests:
- `LicenseState` equality for free/paid

### Manual testing scenarios:
1. Fresh install — app starts in free mode, read-only enforced
2. Purchase — all restrictions lift immediately, badge disappears, toggle unlocks
3. Restore — purchase recognized on fresh install after previous purchase
4. Free mode — browse works, create/write actions show upgrade modal

### StoreKit testing:
- Use Xcode StoreKit testing configuration file for local testing
- Test purchase, restore, refund, and "ask to buy" scenarios

---

## Implementation Status

All code steps are complete:

- [x] LicenseManager — simple free/paid state from StoreKit
- [x] StoreKitManager — StoreKit 2 product, purchase, restore, transaction listener
- [x] Wire into app — injected as EnvironmentObject on all view hierarchies
- [x] Lock read-only toggle — locked in free mode, tapping triggers upgrade sheet
- [x] Free badge — bottom-right overlay, dark red, clickable
- [x] Upgrade modal — sleek sheet with purchase, restore, one-time purchase messaging
- [x] Settings tab — License tab with status, purchase, restore
- [x] Help menu — "Upgrade to Pro" and "Restore Purchase" items
- [x] App sandbox entitlements and ATS configuration
- [x] Unit tests for LicenseState
