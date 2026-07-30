# Root Cause Research

## Production data state

- The running macOS release uses `clipboard-cloud.store` under the app sandbox.
- The active cloud store contains 533 records and zero pinned records.
- The independent local store contains 203 records and one pinned record.
- The pinned local record's `contentHash` does not exist in the cloud store.
- Recent Production CloudKit export events complete successfully, so the missing favorite was never inserted into the active cloud-backed SwiftData store rather than being blocked by the iOS favorite predicate.

## macOS startup path

- `ClipboardRuntimeStore.performInitialBootstrap()` imports only the legacy store and runs repair jobs against the active route.
- A local/cloud cross-route merge is performed only by `rebuildRuntime(syncEnabled:mergeCurrentStore:)` when the sync route is changed.
- `StorageManager.exportStore()` preserves `isPinned` and the complete record payload.
- `StorageManager.importStoreExport(_:)` merges records by `contentHash` and uses logical OR for `isPinned`.
- Therefore, users who enabled cloud sync before favoriting an older record can retain that favorite only in `clipboard-local.store`, with no startup path that compensates it into the cloud-backed store.

## iOS loading path

- `ClipboardStore` already maps `.favorite` to `record.isPinned`, so the favorite query itself is correct.
- `ClipboardHistoryViewModel` loads the launch snapshot into `allRows` but does not seed `rowsByFilter[.all]`.
- When switching to a filter without an exact cache, `applyCachedRowsForSelectedFilter()` cannot use the launch snapshot and clears the visible rows.
- `refresh()` fetches counts, groups, selected-scope items, full keyboard snapshot image payloads, and writes the keyboard snapshot before publishing the selected-scope rows.
- The view only distinguishes initial load from loaded/empty; it cannot distinguish an empty result from a filter request that is still running.

## Relevant files

- macOS: `clipaste/Managers/ClipboardRuntimeStore.swift`
- macOS: `clipaste/Managers/StorageManager.swift`
- macOS: `clipaste/Managers/ClipboardStoreBootstrapper.swift`
- iOS: `/Users/gangz1o/ios-app/Clipaste-iOS/ClipasteiOS/ViewModels/ClipboardHistoryViewModel.swift`
- iOS: `/Users/gangz1o/ios-app/Clipaste-iOS/ClipasteiOS/Views/ClipboardHistoryView.swift`
- iOS: `/Users/gangz1o/ios-app/Clipaste-iOS/ClipasteiOS/ViewModels/SettingsViewModel.swift`
