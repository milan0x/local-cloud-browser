# Deduplication Plan

## Phase 1: Zero-Risk Component Extractions ✅ COMPLETE
**Goal:** Extract verbatim-duplicated code into shared components. No flexibility loss.

### 1A. DoubleClickDetector → `Navigation/DoubleClickDetector.swift` ✅
- Replaced 11 identical copies — saved 465 lines

### 1B. Clipboard helper → `Navigation/Clipboard.swift` ✅
- Replaced 48 private `copyToClipboard` functions — saved 240 lines

### 1C. EmptyStateView → `Navigation/EmptyStateView.swift` ✅
- Replaced 46 identical VStack empty-state patterns — saved 429 lines
- Supports `icon`, `message`, optional `secondaryMessage`

### 1D. StatusBadge → `Navigation/StatusBadge.swift` ✅
- Replaced 105 capsule badge instances across 59 files — saved 833 lines
- Standardized on `.font(.caption2)`, `.fontWeight(.medium)`, `.padding(.horizontal, 5)`, `.padding(.vertical, 1)`

### 1E. ListHeaderButton → `Navigation/ListHeaderButton.swift` ✅
- Replaced 56 inline Button+Image+buttonStyle blocks across 30 files — saved 215 lines
- Expanded hit target (24×24 frame + `contentShape`), hover highlight, standardized styling

### 1F. SegmentedTabPicker → `Navigation/SegmentedTabPicker.swift` ✅
- Replaced 11 Picker+segmented+padding blocks across 11 files — saved ~55 lines
- Generic over `CaseIterable & Hashable & RawRepresentable<String>` enums
- Default padding (8h, 6v) with optional overrides for non-standard cases

**Phase 1 total: 277 replacements, 2,237 lines saved, zero flexibility impact**

---

## Phase 2: Modifier & Pattern Extractions
**Goal:** Extract repeated modifier chains and state patterns.

### 2A. Connection/region change handler → ViewModifier
- 62 files repeat `.onChange(of: appState.connectionVersion)` + `.onChange(of: appState.region)` with identical reset logic
- Create `.resetOnConnectionChange(reset:reload:)` modifier
- **Saves ~300+ lines**

### 2B. Auto-refresh subscription → ViewModifier
- 54 files repeat `.onReceive(appState.autoRefresh.triggerPublisher)` with guard checks
- Create `.onAutoRefresh(skip:action:)` modifier
- **Saves ~200+ lines**

### 2C. Load-with-throttle pattern → Shared helper
- 38 list views repeat identical throttle check (`lastLoadTime`, 2-second guard, `isLoading` guard)
- Extract to a small `LoadThrottle` utility
- **Saves ~200+ lines**

**Phase 2 total: ~700+ lines saved, zero flexibility impact**

---

## Phase 3: Service Base Class (Evaluate First)
**Goal:** Eliminate `client` + `updateClient()` boilerplate from 30 service classes.

- All 30 services declare `private var client: LocalStackClient!` and `func updateClient()`
- Options: protocol with default impl, or base class
- **Evaluate:** Does Swift's ObservableObject work well with a base class? Test with 2-3 services first.
- **Saves ~90 lines** (small, but eliminates a universal pattern)

---

## Phase 4: Evaluate Generic Views (DO NOT auto-proceed)
**Goal:** Assess whether generic list/detail/module shells are worth it.

These are the big-ticket items but carry real risk of over-abstraction:
- Generic list view (38 files, but each has different context menus, selection, columns)
- Generic detail pane (37 files, but each has different sections)
- Generic module shell (28 files, but tabs vs HSplit vs 3-level drill-down)

**Decision criteria:**
- Pick 3 diverse modules (e.g., S3, Lambda, EventBridge)
- Try to fit them into a generic wrapper
- If >80% of code fits naturally → proceed
- If modules need lots of escape hatches → skip, the current duplication is acceptable

---

## Execution Notes
- Each phase is independent — complete one before starting the next
- Phase 1 is safe to do in any order (1A→1B→1C→1D)
- Phase 3 needs a small spike first (test base class with 2 services)
- Phase 4 is exploratory — may not be worth doing
- Always: `swift build` + `swift test` after each sub-phase
