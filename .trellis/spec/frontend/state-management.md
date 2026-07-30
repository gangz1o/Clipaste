# State Management

## Scenario: Cached-first scoped clipboard lists

### 1. Scope / Trigger

Use this contract when a SwiftUI clipboard list switches between database-backed scopes such as all, favorites, content types, or custom groups.

### 2. Signatures

```swift
@MainActor
@Observable
final class ClipboardHistoryViewModel {
    private(set) var rows: [ClipboardRowViewData]
    private(set) var isRefreshingSelectedScope: Bool
}
```

### 3. Contracts

- Seed the `.all` in-memory filter cache whenever a launch snapshot is restored.
- Prefer an exact scope cache; otherwise derive provisional rows from the bounded `.all` cache with the shared filter predicate.
- A scoped database fetch always replaces provisional rows because the `.all` cache may be truncated.
- Set selected-scope loading state when a refresh is scheduled or starts. Only the latest generation may publish rows, clear loading, or publish an error.
- Publish scoped rows immediately after their fetch. Count, group metadata, image-heavy keyboard snapshots, and snapshot file writes are not part of the first-content critical path.
- Keyboard snapshot work uses a separate cancellable, coalesced task; its cancellation or failure must not turn a successful list refresh into an error.
- Views render loading state only: no-cache loading is centered and labeled; cached content remains interactive with a compact accessible progress indicator.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Exact scope cache exists | Render it immediately and refresh asynchronously |
| Only `.all` cache exists | Derive provisional rows with `ClipboardHistoryFilter.contains(_:)` |
| No visible cache exists | Show localized loading instead of empty state |
| Scoped item fetch returns empty | Clear loading, then show the genuine empty state |
| User changes scope during a fetch | Reject the stale generation and leave loading owned by the newer request |
| Keyboard snapshot refresh fails | Keep the published list and do not set the list error |
| Cached rows exist during refresh | Keep scrolling and actions enabled; show only compact progress |

### 5. Good / Base / Bad Cases

- Good: switching from All to Text instantly filters the cached rows, then replaces them with the complete database result.
- Base: a scope with no cache shows `Loading…` / `正在加载…` until its item query completes.
- Bad: clearing the list and displaying an empty-state view before the scope query returns.
- Bad: fetching image payloads and writing the keyboard snapshot before assigning `rows`.

### 6. Tests Required

- Assert launch snapshot restoration seeds `rowsByFilter[.all]`.
- Assert the selected-scope publication call appears before keyboard snapshot scheduling and the scoped refresh body does not fetch image payloads inline.
- Assert the View reads `isRefreshingSelectedScope` and uses localized loading text.
- Build the iOS Debug Simulator target under strict concurrency settings.

### 7. Wrong vs Correct

#### Wrong

```swift
let keyboardItems = try await store.fetchItems(includeImageData: true)
try await saveKeyboardSnapshot(keyboardItems)
rows = fetchedRows
```

#### Correct

```swift
let items = try await store.fetchItems(scope: scope)
publishSelectedScopeRows(items)
scheduleKeyboardSnapshotRefresh(groups: groups)
```
