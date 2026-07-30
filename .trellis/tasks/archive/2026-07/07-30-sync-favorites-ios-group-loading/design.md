# Technical Design

## 1. Boundaries

The change spans two repositories but remains one user-visible data flow:

1. macOS repairs the missing Production CloudKit input by copying only locally pinned records into the active cloud-backed store.
2. iOS renders available cached rows immediately, exposes filter-refresh state through its `@Observable` ViewModel, and removes keyboard snapshot work from the selected-filter critical path.

No CloudKit container, schema, record model, or third-party dependency changes are required.

## 2. macOS favorite recovery

### Store contract

Add a throwing store export dedicated to pinned records. It fetches only records where `isPinned == true`, maps the complete existing `ClipboardRecordExport` payload, and includes only group definitions referenced by those records. Non-pinned history never enters the recovery payload.

The cloud target continues to use `importStoreExport(_:)`, preserving the existing contracts:

- deduplicate by `contentHash`;
- merge `isPinned` with logical OR;
- preserve richer existing fields when the incoming optional field is absent;
- retain group membership and referenced group metadata.

### Startup orchestration

`ClipboardRuntimeStore.performInitialBootstrap()` invokes a versioned recovery only when the active route is cloud-backed and the stored recovery version is older than the current version.

Data flow:

```text
cloud startup
  -> open/reuse local runtime off the main thread
  -> export pinned-only payload
  -> if empty: mark recovery complete
  -> import payload into active cloud store
  -> mark recovery complete
  -> continue normal sync-anchor and repair flow
```

The completion marker is written only after the pinned export was read successfully and the cloud-store import completed successfully. Any open, fetch, or import error leaves the marker unchanged so the next startup retries. Diagnostics record start, imported record/group counts, empty completion, and failure.

This is intentionally one-way and one-time. It does not merge the entire local store and does not alter normal route-switch behavior.

## 3. iOS cached-first filtering

### Cache seeding and derivation

When a launch snapshot is loaded, seed `rowsByFilter[.all]` as well as `allRows`. On filter selection:

1. use an exact filter cache when available;
2. otherwise use the `.all` cache as a bounded source and derive visible rows through the existing `ClipboardHistoryFilter.contains(_:)` logic;
3. otherwise show no rows while exposing loading state.

Derived rows are provisional because the `.all` cache is capped. The selected-scope database query still runs immediately and replaces them with the complete scoped result.

### Refresh state contract

Expose `private(set) var isRefreshingSelectedScope` from `ClipboardHistoryViewModel`.

- Set it when a selected-scope refresh is scheduled or begins.
- Clear it only when the latest generation publishes rows or reports an error.
- Cancelled or stale generations must not clear the state owned by a newer request.
- Existing rows remain interactive while the flag is true.

Views render this state only; they do not infer request lifecycle or perform filtering.

## 4. iOS refresh pipeline

Reorder `refresh()` so selected-scope rows are the first database result published after any pending keyboard import:

```text
import pending keyboard items
  -> fetch selected-scope items
  -> generation check
  -> publish rows and clear selected-scope loading
  -> fetch count and groups
  -> update paging/filter metadata
  -> schedule coalesced keyboard snapshot refresh
```

The keyboard snapshot refresh owns a separate cancellable task. Repeated refreshes cancel and replace pending snapshot work. Its image-heavy fetch and disk write occur after selected rows are published and never control `isRefreshingSelectedScope`.

The existing generation/filter/query checks remain the authority for preventing stale row publication during rapid filter changes.

## 5. Loading UI

- If no rows are available and `isRefreshingSelectedScope == true`, show a centered `ProgressView` with localized `Loading…` / `正在加载…` text.
- If rows are already visible and a refresh is running, keep the list interactive and show a compact progress indicator beside the filter segmented control.
- Show the empty-state view only after loading has completed and the current result is genuinely empty.
- Search's “enter a keyword” state retains priority when the search query is empty.

The new localized string remains in `AppStrings`, matching the project's existing bilingual localization approach.

## 6. Compatibility and rollback

- Recovery uses a new UserDefaults version key; removing the call disables future runs without changing already imported records.
- Re-importing is idempotent through `contentHash` merge semantics.
- iOS changes are internal ViewModel/View behavior and do not change persisted launch-cache format.
- Preserve the user's existing uncommitted iOS `ClipasteiOS.xcodeproj/project.pbxproj` version changes; no project-file edit is planned.
