# Implementation Plan

## 1. macOS pinned-only export

- [x] Add a throwing `StorageManager` / store-actor API that exports only pinned records with complete metadata.
- [x] Include only group definitions referenced by exported pinned records.
- [x] Keep the existing full-store export unchanged for route switching and legacy migration.
- [x] Add a focused regression test or executable harness covering pinned-only selection, referenced groups, and exclusion of non-pinned history.

## 2. macOS startup recovery

- [x] Add a versioned recovery key and a private startup recovery method in `ClipboardRuntimeStore`.
- [x] Run recovery only for the active cloud route and only while its version is incomplete.
- [x] Open or reuse the local runtime without blocking the main thread.
- [x] Import through `importStoreExport(_:)`, record diagnostic counts, and set the completion version only after success.
- [x] Verify empty local favorites complete without importing unrelated records and failures remain retryable.

## 3. iOS cached-first ViewModel

- [x] Seed `.all` filter cache from the launch snapshot.
- [x] Add latest-generation selected-scope loading state to the `@Observable` ViewModel.
- [x] Keep exact-cache-first and `.all`-derived fallback behavior when filters change.
- [x] Preserve generation, filter, scope, and query guards during rapid switching.

## 4. iOS non-blocking refresh pipeline

- [x] Publish selected-scope items before count/group/keyboard snapshot work.
- [x] Move keyboard snapshot fetching and saving into a separate coalesced cancellable task.
- [x] Ensure snapshot failures do not replace successful list results with an error.
- [x] Keep paging counts, custom groups, launch-cache saves, and keyboard-import behavior correct.

## 5. iOS loading presentation

- [x] Add `Loading…` / `正在加载…` to `AppStrings`.
- [x] Show centered labeled progress only when the current scope has no visible cached rows.
- [x] Show compact progress by the filter control while cached rows remain visible.
- [x] Delay genuine empty-state presentation until the current scope finishes loading.

## 6. Verification

- [x] Run the focused macOS recovery regression test/harness.
- [x] Run macOS Debug build with the project build settings.
- [x] Run iOS Debug Simulator build using XcodeBuildMCP.
- [x] Verify English and Chinese loading strings are referenced by the loading UI.
- [x] Run `git diff --check` in both repositories.
- [x] Confirm `/Users/gangz1o/ios-app/Clipaste-iOS/ClipasteiOS.xcodeproj/project.pbxproj` still contains only the user's pre-existing version edits.
- [x] Review final diffs for full-history upload, stale-result publication, and accidental project-file changes.

## Verification Evidence

- `FavoriteCloudRecoverySourceTests passed`
- `ClipboardHistoryLoadingSourceTests passed`
- macOS Debug clean build: `BUILD SUCCEEDED`
- iOS Debug Simulator build through XcodeBuildMCP: `Build succeeded`
- Both repositories: `git diff --check` exited successfully
- iOS project file remained outside the task commit scope
