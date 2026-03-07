# Monetization Implementation Plan

## Overview
14-day free trial with full access, then read-only limited mode. One-time $9.99 IAP to unlock permanently.

## Pricing Model Summary

| Phase | Duration | Access |
|-------|----------|--------|
| Trial | Days 1-14 | Full unrestricted access, subtle countdown visible |
| Limited Mode | Day 15+ | Read-only (browse/delete OK, create/write blocked) |
| Paid | Permanent | Full access, no restrictions |

---

## Implementation Steps

### Step 1: LicenseManager (new file)

**File:** `Sources/LocalCloudBrowser/App/LicenseManager.swift`

Create a `@MainActor` `ObservableObject` that is the single source of truth for license state.

```
enum LicenseState {
    case trial(daysRemaining: Int)
    case limited
    case paid
}
```

**Responsibilities:**
- On init, read `trialStartDate` from UserDefaults. If nil, set it to `Date()` (first launch).
- Compute `LicenseState` from the difference between now and `trialStartDate`.
- Expose `isPaid: Bool` backed by StoreKit 2 entitlement check.
- Expose `canPerformWriteAction: Bool` — returns `true` if `.trial` or `.paid`.
- Expose `daysRemaining: Int?` — returns remaining days during trial, nil otherwise.
- Expose `shouldShowUpgradeModal: Bool` — set to `true` when a write action is attempted in limited mode.
- Trust system clock (no server validation).

**UserDefaults keys:**
- `LicenseManager.trialStartDate` — `Date`, set once on first launch
- StoreKit 2 handles purchase persistence (no manual key needed)

**Important:** Use `@AppStorage` or `UserDefaults.standard` for the trial date. Do NOT use Keychain — it's overkill for a date stamp and would complicate the implementation.

### Step 2: StoreKit 2 Integration (new file)

**File:** `Sources/LocalCloudBrowser/App/StoreKitManager.swift`

**Product setup:**
- One non-consumable IAP: product ID `com.localcloudbrowser.pro` (or similar)
- Use StoreKit 2 (`Product`, `Transaction`) — modern async API, no delegates

**Responsibilities:**
- `loadProduct()` — fetch the product from App Store
- `purchase()` — initiate purchase flow
- `restorePurchases()` — call `Transaction.currentEntitlements`
- `isPurchased: Bool` — check `Transaction.currentEntitlement(for:)`
- Listen for `Transaction.updates` on app launch to catch external purchases/refunds

**Integration with LicenseManager:**
- LicenseManager holds a reference to StoreKitManager
- On init, LicenseManager checks `storeKitManager.isPurchased` to determine if state is `.paid`
- After successful purchase, LicenseManager transitions to `.paid` and publishes the change

### Step 3: Wire LicenseManager into the App

**File to modify:** `Sources/LocalCloudBrowser/App/LocalCloudBrowserApp.swift`

- Create `LicenseManager` as a `@StateObject` alongside `AppState`
- Inject it as `.environmentObject(licenseManager)` on all view hierarchies:
  - Main `ContentView`
  - `S3BrowserWindow`
  - `Settings`

### Step 4: Gate Write Actions via ReadOnlyInterceptor

**File to modify:** `Sources/LocalCloudBrowser/Safety/ReadOnlyInterceptor.swift`

Current signature:
```swift
static func allowsRequest(method: String, isReadOnly: Bool) -> Bool
```

**Change:** Add license state awareness. Two approaches (pick one during implementation):

**Option A — Modify the interceptor directly:**
Add a `isLimited: Bool` parameter:
```swift
static func allowsRequest(method: String, isReadOnly: Bool, isLimited: Bool) -> Bool
```
If `isLimited` is true, treat as read-only regardless of the toggle.

**Option B — Force read-only at the AppState level:**
In limited mode, `LicenseManager` forces `appState.isReadOnly = true` and the UI disables the toggle. The interceptor doesn't need to change at all.

**Recommendation:** Option B is simpler — fewer code paths, the interceptor stays dumb, and the lock toggle UI naturally reflects the state.

### Step 5: Lock the Read-Only Toggle in Limited Mode

**File to modify:** `Sources/LocalCloudBrowser/Navigation/SidebarView.swift`

Current read-only toggle (line ~378-387):
```swift
private var readOnlyToggle: some View {
    Button {
        appState.isReadOnly.toggle()
    } label: {
        Image(systemName: appState.isReadOnly ? "lock.fill" : "lock.open")
            .foregroundStyle(appState.isReadOnly ? .orange : .secondary)
    }
    .buttonStyle(.plain)
}
```

**Changes:**
- Read `licenseManager` from environment
- If `.limited`: disable the button, keep it locked appearance, add help text "Upgrade to Pro to unlock write access"
- If `.trial` or `.paid`: current behavior unchanged
- On tap while limited: set `licenseManager.shouldShowUpgradeModal = true` instead of toggling

### Step 6: Trial Countdown Indicator

**File to modify:** `Sources/LocalCloudBrowser/Navigation/ContentView.swift`

Add a new `ToolbarItem` next to the existing region badge (line ~19):

**During trial:**
- Show subtle text: "12 days remaining" with a small clock icon
- Muted color (.secondary), not attention-grabbing
- Clicking it could show a small popover explaining the trial

**During limited mode:**
- Show "Limited Mode" badge in a capsule shape (similar to the existing "Preview" badge style)
- Tapping opens the upgrade modal/sheet

**After purchase:**
- Nothing shown — toolbar item is hidden

### Step 7: Upgrade Modal / Purchase Sheet (new file)

**File:** `Sources/LocalCloudBrowser/App/UpgradeView.swift`

A SwiftUI `.sheet` that appears when a write action is attempted in limited mode.

**Design requirements (per user request):**
- Sleek, native macOS feel — not a cheap paywall
- Premium look, no guilt-tripping language
- Brief value description of what they're unlocking

**Content:**
```
[App Icon or cloud symbol]

Unlock Full Access

Create, modify, and manage resources across all 28 AWS services
with no restrictions.

$9.99 — one-time purchase

[Purchase]     [Restore Purchase]

[Not Now]
```

**Trigger points:**
- Any create/write action attempted in limited mode
- Tapping the "Limited Mode" toolbar badge
- Tapping the locked read-only toggle
- Optionally: a menu item under Help > "Upgrade to Pro"

**Presentation:**
- Use `.sheet` — modal, centered, not dismissable by clicking outside (use explicit "Not Now")
- After successful purchase: dismiss sheet, show brief confirmation (checkmark animation or similar), remove all restrictions immediately

### Step 8: Settings Integration

**File to modify:** `Sources/LocalCloudBrowser/App/SettingsView.swift`

Add a new tab: **"License"** or **"Pro"**

**Content:**
- Current license state: "Trial (8 days remaining)" / "Limited Mode" / "Pro"
- If trial/limited: Purchase button + Restore Purchase button
- If paid: "Thank you for supporting Local Cloud Browser" message
- Trial start date (informational)

### Step 9: Ensure Restrictions Are Lifted on Purchase

**Critical checklist — all of these must react to `licenseManager.isPaid` changing to `true`:**

1. `appState.isReadOnly` becomes user-controllable again (toggle unlocked)
2. Read-only toggle in SidebarView re-enables
3. Toolbar badge disappears
4. Upgrade modal dismisses if open
5. `ReadOnlyInterceptor` stops force-blocking (because `isReadOnly` is no longer force-locked)
6. All module views can perform write actions immediately

**How:** Since `LicenseManager` is an `ObservableObject` injected via `@EnvironmentObject`, all views will re-render automatically when `isPaid` changes. The key is to make sure the read-only toggle and interceptor check `licenseManager` state, not just `appState.isReadOnly`.

### Step 10: Restore Purchase Flow

**Locations where "Restore Purchase" should be accessible:**
1. The upgrade modal (Step 7)
2. Settings > License tab (Step 8)
3. Help menu — add "Restore Purchase" item

**File to modify for Help menu:** `Sources/LocalCloudBrowser/App/HelpCommands.swift`

**Behavior:**
- Calls `storeKitManager.restorePurchases()`
- If found: transition to `.paid`, show confirmation
- If not found: show "No previous purchase found" message

---

## Files Summary

### New files (4):
| File | Purpose |
|------|---------|
| `App/LicenseManager.swift` | License state machine (trial/limited/paid) |
| `App/StoreKitManager.swift` | StoreKit 2 product, purchase, restore |
| `App/UpgradeView.swift` | Purchase modal sheet |
| `App/TrialBadgeView.swift` | Toolbar trial countdown / limited mode badge (optional — could be inline in ContentView) |

### Modified files (6):
| File | Change |
|------|--------|
| `App/LocalCloudBrowserApp.swift` | Create and inject LicenseManager |
| `App/SettingsView.swift` | Add License/Pro tab |
| `App/HelpCommands.swift` | Add "Restore Purchase" menu item |
| `Navigation/ContentView.swift` | Add trial/limited toolbar badge |
| `Navigation/SidebarView.swift` | Lock read-only toggle in limited mode, trigger upgrade modal |
| `Safety/ReadOnlyInterceptor.swift` | Possibly unchanged if using Option B (force read-only via AppState) |

### Unchanged:
| File | Why |
|------|-----|
| `Networking/CloudClient.swift` | Already checks `isReadOnly` via the interceptor — no changes needed |
| All module views | They already respect `isReadOnly` — no per-module changes needed |
| `Settings/ConnectionProfile.swift` | No license-related changes |

---

## App Store Requirements Checklist

- [ ] Non-consumable IAP registered in App Store Connect
- [ ] Product ID configured in StoreKitManager
- [ ] StoreKit 2 configuration file for testing (`.storekit` file)
- [ ] App Review notes explaining the trial model
- [ ] Privacy policy (required for paid apps)
- [ ] Restore Purchase accessible without paywall (App Store Review Guideline 3.1.1)
- [ ] App sandbox entitlements for Mac App Store distribution
- [ ] Signing with Developer ID / Mac App Store certificate

---

## Testing Plan

### Manual testing scenarios:
1. Fresh install — trial starts, 14 days shown, full access works
2. Day 15 — app transitions to limited mode on launch
3. Limited mode — browse works, create shows upgrade modal, delete works
4. Purchase — all restrictions lift immediately, badge disappears, toggle unlocks
5. Restore — purchase recognized on fresh install after previous purchase
6. Clock forward — set system date ahead 14 days, verify limited mode activates
7. Clock backward — set date back, verify trial doesn't re-extend (use `min(trialStartDate, now)` logic)

### StoreKit testing:
- Use Xcode StoreKit testing configuration file for local testing
- Test purchase, restore, refund, and "ask to buy" scenarios

---

## Implementation Order

Recommended sequence for building this:

1. **LicenseManager** — the state machine, no UI yet
2. **StoreKitManager** — product loading, purchase, restore
3. **Wire into app** — inject as EnvironmentObject
4. **Lock read-only toggle** — first visible behavior change
5. **Toolbar badge** — trial countdown and limited mode indicator
6. **Upgrade modal** — the purchase sheet
7. **Settings tab** — license info and restore
8. **Help menu** — restore purchase item
9. **Testing** — all scenarios above
10. **App Store Connect** — IAP setup, screenshots, review notes
