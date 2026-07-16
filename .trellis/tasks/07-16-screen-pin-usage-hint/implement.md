# Screen Pin Usage Hint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one localized instruction below the screen-pinning toggle without restoring the removed size description.

**Architecture:** Keep the change entirely in the SwiftUI settings presentation and String Catalog. Existing `@Observable ScreenPinViewModel` state and screen-pin business logic remain unchanged.

**Tech Stack:** SwiftUI, String Catalog, jq, xcodebuild.

---

### Task 1: Add the localized usage hint

**Files:**
- Modify: `clipaste/Views/AdvancedSettingsView.swift`
- Modify: `clipaste/Localizable.xcstrings`

- [x] **Step 1: Run the failing localization assertion**

Run:

```bash
jq -e '.strings["Press and hold the source app icon on an image history item, then drag it anywhere on the screen and release to pin the image."]' clipaste/Localizable.xcstrings
```

Expected: exit code 1 because the instruction key does not exist.

- [x] **Step 2: Add the SwiftUI instruction**

Place this directly below the screen-pinning toggle:

```swift
Text("Press and hold the source app icon on an image history item, then drag it anywhere on the screen and release to pin the image.")
    .font(.subheadline)
    .foregroundStyle(.secondary)
```

- [x] **Step 3: Add all seven String Catalog localizations**

Add the English source key with `extractionState: manual` and translated `stringUnit` values for `en`, `zh-Hans`, `zh-Hant`, `ja`, `ko`, `de`, and `fr`.

- [x] **Step 4: Verify localization and removed-copy boundaries**

Run:

```bash
jq empty clipaste/Localizable.xcstrings
rg -n "Press and hold the source app icon" clipaste/Views/AdvancedSettingsView.swift clipaste/Localizable.xcstrings
```

Expected: valid JSON and matches only for the new usage hint.

- [x] **Step 5: Run the clean build**

Run:

```bash
xcodebuild -project clipaste.xcodeproj -scheme Clipaste -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/clipaste-screen-pin-usage-hint clean build -quiet
```

Expected: exit code 0 with no warnings.
