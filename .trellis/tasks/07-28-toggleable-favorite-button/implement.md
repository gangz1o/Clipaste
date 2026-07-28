# Hover Favorite Button Implementation Plan

## Implementation

- [x] Add a reusable SwiftUI favorite button component with localized state labels, themed selected/pressed feedback, and a compact card-sized hit target.
- [x] Add the control to the horizontal card's bottom-leading overlay, gated by hover/selection and quick-paste state.
- [x] Add the control to the non-compact vertical row's inline-action area, preserving AI and quick-paste behavior.
- [x] Reuse `ClipboardViewModel.pinItem(item:)` and suppress ancestor single-click paste before toggling.
- [x] Preserve normal card selection when single-click paste is suppressed, and expire unconsumed suppression after the current input event.
- [x] Confirm no setting, preference key, persistence path, or third-party dependency is added.

## Validation

- [x] Verify the existing favorite accessibility strings cover every supported localization.
- [x] Search the diff for forbidden `ObservableObject` additions, new `@AppStorage` settings, and duplicated favorite persistence logic.
- [x] Run `jq empty clipaste/Localizable.xcstrings`.
- [x] Run `git diff --check`.
- [x] Run `xcodebuild -project clipaste.xcodeproj -scheme Clipaste -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/clipaste-hover-favorite-button build -quiet`.

## Risk and Rollback Points

- The parent card uses simultaneous tap gestures; validate the favorite action calls the existing paste-suppression hook before toggling.
- Keep horizontal and vertical call sites visually independent so either placement can be reverted without touching favorite state handling.
