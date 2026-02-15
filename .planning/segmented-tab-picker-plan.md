# Plan: Extract SegmentedTabPicker Component

## Goal
Extract the repeated segmented `Picker` pattern into a shared `SegmentedTabPicker` component in `Navigation/SegmentedTabPicker.swift`. Zero risk — identical to prior Phase 1 extractions.

## Component Design

**File:** `Sources/LocalStackNavigator/Navigation/SegmentedTabPicker.swift`

```swift
import SwiftUI

/// A segmented picker for switching between tab cases.
///
/// Generic over any `CaseIterable + Hashable + RawRepresentable<String>` enum.
/// Replaces the repeated Picker+segmented+padding pattern across module views.
struct SegmentedTabPicker<T: CaseIterable & Hashable & RawRepresentable>: View where T.RawValue == String, T.AllCases: RandomAccessCollection {
    @Binding var selection: T
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat

    init(selection: Binding<T>, horizontalPadding: CGFloat = 8, verticalPadding: CGFloat = 6) {
        self._selection = selection
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(T.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
    }
}
```

## Files to Change (11 files)

All replacements are mechanical: replace the 6-line Picker block with a single `SegmentedTabPicker(selection:)`.

### Wave 1 — Standard padding (8h, 6v) — 7 files

These use the exact default padding, so no overrides needed.

| # | File | Line | Binding | Enum |
|---|------|------|---------|------|
| 1 | `Modules/EC2/EC2EntityListView.swift` | ~67 | `$entityType` | `EC2EntityType` |
| 2 | `Modules/IAM/IAMEntityListView.swift` | ~52 | `$entityType` | `IAMEntityType` |
| 3 | `Modules/CloudWatch/CloudWatchModuleView.swift` | ~92 | `$tab` | `CloudWatchTab` |
| 4 | `Modules/Kinesis/KinesisModuleView.swift` | ~109 | `$tab` | `KinesisTab` |
| 5 | `Modules/Config/ConfigModuleView.swift` | ~103 | `$tab` | `ConfigTab` |
| 6 | `Modules/Route53/Route53ModuleView.swift` | ~110 | `$tab` | `Route53Tab` |
| 7 | `Modules/EventBridge/EventBridgeModuleView.swift` | ~111 | `$tab` | `EventBridgeTab` |

**Before (each file):**
```swift
Picker("Tab", selection: $tab) {
    ForEach(SomeTab.allCases, id: \.self) { t in
        Text(t.rawValue).tag(t)
    }
}
.pickerStyle(.segmented)
.padding(.horizontal, 8)
.padding(.vertical, 6)
```

**After:**
```swift
SegmentedTabPicker(selection: $tab)
```

### Wave 2 — Non-standard padding — 4 files

These have different padding or sizing. Pass custom values.

| # | File | Line | Binding | Custom params |
|---|------|------|---------|---------------|
| 8 | `Modules/APIGateway/APIGatewayAPIBrowserView.swift` | ~47 | `$selectedTab` | `horizontalPadding: 16, verticalPadding: 8` |
| 9 | `Modules/StepFunctions/StepFunctionsModuleView.swift` | ~103 | `$selectedTab` | `horizontalPadding: 12, verticalPadding: 8` |
| 10 | `Modules/CloudFormation/CloudFormationStackBrowserView.swift` | ~41 | `$selectedTab` | `horizontalPadding: 16, verticalPadding: 8` |
| 11 | `Modules/DynamoDB/DynamoDBBrowserView.swift` | ~19 | `$selectedTab` | `horizontalPadding: 0, verticalPadding: 6` + `.frame(width: 200)` |

**After (files 8 & 10):**
```swift
SegmentedTabPicker(selection: $selectedTab, horizontalPadding: 16, verticalPadding: 8)
```

**After (file 9):**
```swift
SegmentedTabPicker(selection: $selectedTab, horizontalPadding: 12, verticalPadding: 8)
```

**After (file 11 — DynamoDB):**
```swift
SegmentedTabPicker(selection: $selectedTab, horizontalPadding: 0, verticalPadding: 6)
    .frame(width: 200)
```

## Files NOT to change

These are NOT tab navigation pickers — they're form controls or inline selectors:

- `SES/SESVerifyIdentityView.swift` — form picker (Email/Domain type)
- `SES/SESSendEmailView.swift` — form picker (body format)
- `SES/SESSentEmailBrowserView.swift` — inline body tab (fixed width 150)
- `DynamoDB/DynamoDBPutItemView.swift` — bool true/false in form
- `DynamoDB/DynamoDBItemBrowserView.swift` — BrowseMode picker (fixed width 180)
- `CloudWatch/CloudWatchMetricChartView.swift` — TimeRange & Statistic chart controls

## Execution Steps

1. ✅ **Create** `Sources/LocalStackNavigator/Navigation/SegmentedTabPicker.swift` with the code above
2. ✅ **Run** `swift build` — verify the new file compiles
3. ✅ **Wave 1:** Replace all 7 standard-padding files → `swift build`
4. ✅ **Wave 2:** Replace all 4 non-standard files → `swift build`
5. ✅ **Run** `swift test` — all 477 tests must pass
6. ✅ **Update** `.planning/deduplication-plan.md` — add as Phase 1F with totals
7. ✅ **Commit** all changed files + new file
8. ✅ **Push**

## Impact

- **11 files changed**, 11 Picker blocks replaced
- **~55 lines saved** (each block is 6 lines → 1 line, minus new component file)
- Future tab additions only need `SegmentedTabPicker(selection: $newTab)` — one line
- Zero flexibility loss — custom padding available via parameters
