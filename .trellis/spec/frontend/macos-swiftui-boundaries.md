# macOS SwiftUI Feature Boundaries

## Scenario: Automatic remote enrichment for clipboard content

### 1. Scope / Trigger

Use this contract when clipboard capture or history loading automatically fetches remote metadata such as a page title or favicon.

### 2. Contracts

- Automatic enrichment must use a streaming response body with a hard byte limit. Checking `Data.count` after `URLSession.data(for:)` does not limit network transfer or peak memory.
- Reject known oversized `Content-Length` values before consuming the body. Unknown or incorrect lengths must still stop at the streaming limit and cancel the underlying task.
- Validate HTTP status, final redirect URL, and declared MIME type before reading the body. Missing MIME types may use a bounded compatibility path.
- Bound both the size of each secondary resource and the number of candidates. A per-favicon limit alone does not bound total traffic when a page declares many icons.
- Every automatic entry point must honor the same persisted opt-out. Apply the gate to the network call only; local enrichment such as syntax highlighting must keep its existing behavior.
- Coalesce concurrent enrichment for the same content hash and clear the in-flight marker on success, failure, timeout, and cancellation.
- Never log the full clipboard URL, query, response body, or metadata content.

### 3. Tests Required

- A mock transport that ignores `Range` must prove an unknown-length response is cancelled at the body limit.
- A declared oversized response must be rejected without consuming body bytes.
- Tests must cover valid metadata, invalid MIME types, candidate-count limits, and the persisted opt-out.
- Run the full macOS build after changing capture, storage-task, or settings boundaries.

## Scenario: Interactive floating media windows

### 1. Scope / Trigger

Use this contract when a SwiftUI feature needs system drag sessions, independent AppKit windows, large image loading, or persisted feature settings.

### 2. Signatures

```swift
@MainActor
@Observable
final class FeatureViewModel {
    var isEnabled: Bool
    var initialSizeScale: Double
}

@MainActor
protocol FloatingWindowCoordinating: AnyObject {
    func show(image: NSImage, at screenPoint: CGPoint, initialSizeScale: Double)
    func closeAll()
}
```

### 3. Contracts

- New shared state uses `@MainActor @Observable`; do not add `ObservableObject`.
- Do not place `@AppStorage` inside an `@Observable` type. Read and write `UserDefaults` explicitly in the ViewModel, and expose a bindable property to SwiftUI.
- SwiftUI Views render state and forward interaction only. File I/O, eligibility decisions, cancellation, and window lifecycle belong outside the View.
- Extend `ClipboardImagePipeline` for image display workloads. Reuse its background ImageIO path and bounded `NSCache` instead of synchronously constructing full-resolution images.
- When one source gesture has two product intents, use separate hit targets and separate drag sessions. A source-app icon can act as the dedicated pin target without adding another visible control. Do not infer intent from a failed external drop.
- Modifier order is part of the drag contract: apply the card's external `.onDrag` before adding the dedicated icon-target overlay. If `.onDrag` wraps the overlay, SwiftUI wins the drag sequence even when the embedded AppKit view wins initial hit testing.
- AppKit bridges are allowed only for capabilities unavailable in the deployment-target SwiftUI API, such as drag-ended screen coordinates and borderless window movement.
- At drag completion, sample `NSEvent.mouseLocation` as the authoritative AppKit global coordinate. Do not rely on a potentially stale drag-session callback parameter for final placement.
- A full-window movement bridge must return `nil` from hit testing near resize edges. Never call `performDrag(with:)` from the same border region AppKit uses for native resizing.
- Do not mutate `minSize`, `maxSize`, or call `setFrame` from a screen-change callback while `NSWindow.inLiveResize` is true. Record a pending refresh and apply it from `windowDidEndLiveResize`.
- Assigning an `NSHostingController` can replace a borderless window's initial content size. Reapply the calculated initial frame after installing the content controller, before presenting the window.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Feature disabled | Hide the interaction target, cancel pending tasks, close owned windows |
| Unsupported content | Do not start I/O or create a drag source |
| Missing or invalid image | Do not create an empty window; show localized feedback |
| Task cancelled after decode | Do not create a delayed window or publish stale UI state |
| Large source image | Downsample off-main to the display pixel budget |
| Window moves to another screen | Refresh size limits without clamping every move event |
| Dedicated icon target starts dragging | Its AppKit drag source receives `mouseDragged`; the enclosing card drag provider is not requested |
| Screen changes during live resize | Defer size-constraint refresh until `windowDidEndLiveResize` |
| Pointer is on a resize border | Window movement overlay does not hit; AppKit owns the resize gesture |
| SwiftUI content controller installed | Reapply the calculated initial frame so intrinsic content size cannot collapse the window |

### 5. Good / Base / Bad Cases

- Good: a repeated request for the same image and pixel budget joins an in-flight task or hits `NSCache`.
- Base: a valid image creates one independently managed floating window on the drop-point screen.
- Bad: `Data(contentsOf:)`, ImageIO decode, or full-resolution image creation runs on `@MainActor`.
- Bad: `windowDidMove` clamps a window to its current screen on every event, preventing cross-display movement.

### 6. Tests Required

- Pure geometry tests assert aspect ratio, configured original-image scale, release-point anchoring, screen margins, and min/max sizes.
- Render-budget tests assert backing-scale calculation and hard pixel caps.
- ViewModel tests inject fake image/window services and assert default settings, persistence, type filtering, cancellation, and no delayed window creation.
- Full app build must compile String Catalog entries for every supported locale.
- A window-backed drag harness must exercise mouse down, drag, and mouse up with the same modifier ordering used by the production card.
- Window interaction tests must cover resize-border hit regions and deferred constraint refresh; a runtime harness must stress repeated resizing on every attached display.

### 7. Wrong vs Correct

#### Wrong

```swift
struct ItemView: View {
    var body: some View {
        Button("Pin") {
            let data = try? Data(contentsOf: fileURL)
            ScreenWindowManager.shared.show(data: data)
        }
    }
}
```

#### Correct

```swift
struct ItemView: View {
    @Environment(FeatureViewModel.self) private var viewModel

    var body: some View {
        Button("Pin") {
            viewModel.createPin(for: item, at: NSEvent.mouseLocation)
        }
    }
}
```

The View forwards intent. The ViewModel validates and cancels work, the shared image pipeline performs bounded off-main decoding, and the AppKit coordinator owns windows.

#### Wrong: mutate constraints during live resize

```swift
func windowDidChangeScreen(_ notification: Notification) {
    applySizeConstraints()
    window.setFrame(clampedFrame, display: true)
}
```

This can re-enter AppKit's active resize transaction when a window crosses displays.

#### Correct: defer until live resize ends

```swift
func windowDidChangeScreen(_ notification: Notification) {
    guard window.inLiveResize == false else {
        needsConstraintRefresh = true
        return
    }
    refreshConstraints()
}

func windowDidEndLiveResize(_ notification: Notification) {
    guard needsConstraintRefresh else { return }
    needsConstraintRefresh = false
    refreshConstraints()
}
```

The resize transaction owns geometry until `windowDidEndLiveResize`; constraint updates happen once afterward.

## Scenario: Controls nested inside clipboard-item tap gestures

### 1. Scope / Trigger

Use this contract when adding a `Button`, `Menu`, or other control inside a clipboard item that already owns ancestor `simultaneousGesture` handlers for selection and single-click paste.

### 2. Signatures

```swift
@MainActor
func suppressNextPaste(for itemID: UUID)

@MainActor
func pasteToActiveApp(item: ClipboardItem)
```

### 3. Contracts

- A nested control that must not paste calls `suppressNextPaste(for:)` before forwarding its domain intent.
- If single-click paste replaced the normal ancestor selection gesture, the nested control forwards the existing primary-selection intent explicitly.
- Paste suppression is event-scoped. `suppressNextPaste(for:)` must remove an unconsumed marker after yielding once on `MainActor`; a stale marker must never suppress a later keyboard, accessibility, or intentional paste action.
- The View renders the control and forwards interaction only. Favorite state still changes through `ClipboardViewModel.pinItem(item:)` and `setFavoriteState(for:isFavorite:)`.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Single-click paste enabled, nested control clicked | Select the item, perform the control action, and do not paste |
| Normal selection mode, nested control clicked | Ancestor selection remains active and the control action runs once |
| Suppression marker is not consumed in the current event | Remove it after one main-actor yield |
| Later keyboard or accessibility paste | Never consume a marker left by an earlier control click |

### 5. Good / Base / Bad Cases

- Good: clicking the favorite button selects the row when needed, toggles the existing favorite state, and cannot paste the item.
- Base: clicking the card background keeps the configured selection or paste behavior.
- Bad: inserting an item ID into `suppressedPasteItemIDs` without expiry; the next unrelated paste can be silently dropped.

### 6. Tests Required

- With single-click paste enabled, assert a nested-control click updates selection and does not call the paste engine.
- Assert consumed suppression prevents exactly the current paste attempt.
- Assert unconsumed suppression expires before a later explicit paste.
- Rebuild both horizontal and vertical clipboard layouts after changing the shared nested-control contract.

### 7. Wrong vs Correct

#### Wrong

```swift
func nestedControlAction() {
    suppressedPasteItemIDs.insert(item.id)
    performAction()
}
```

#### Correct

```swift
func suppressNextPaste(for itemID: UUID) {
    suppressedPasteItemIDs.insert(itemID)

    Task { @MainActor [weak self] in
        await Task.yield()
        self?.suppressedPasteItemIDs.remove(itemID)
    }
}
```

## Scenario: Filtered horizontal list positioning

### 1. Scope / Trigger

Use this contract when a group, smart filter, search scope, or refresh replaces `displayedItemIDs` and also changes the primary selection in the horizontal clipboard panel.

### 2. Signatures

```swift
@MainActor
func requestListScroll(to itemID: UUID, animated: Bool)

private func scrollToItem(
    with proxy: ScrollViewProxy,
    itemID: UUID,
    animated: Bool
)
```

### 3. Contracts

- Do not wrap group or filter data-source mutations in a broad `withAnimation`. Animate the tab's `isSelected` and hover styling locally with value-scoped modifiers.
- When `displayedItemIDs`, first-item selection, and `listScrollRequest` change as one logical filter result, handle the scroll request in the same SwiftUI update cycle. Do not add another `DispatchQueue.main.async` hop.
- Initial appearance may yield once before positioning because the lazy stack needs its first layout pass. Use a cancellable SwiftUI `.task`, not a persistent queue callback.
- Preserve explicit animated scrolling for keyboard navigation; group-switch first-item resets remain unanimated.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Switch between two filters | Replace content and position the new first item without an intermediate old offset |
| Switch back to All | Insert restored cards without spring animation |
| Horizontal list first appears | Yield once, then position the existing primary selection |
| Keyboard selection moves | Center the target using the explicit short animation |
| Group tab selection changes | Animate only the tab's visual state |

### 5. Good / Base / Bad Cases

- Good: the filter publishes new IDs, resets selection, and the list consumes the resulting scroll request in one view update.
- Base: keyboard navigation issues an animated request to an item already in the current list.
- Bad: new IDs render at the old offset, then a queued callback moves the list one frame later.
- Bad: a spring transaction surrounds `showSmartFilter`, `showBuiltInGroup`, or another data-source intent.

### 6. Tests Required

- A regression check must reject broad animation wrappers around group scope mutations.
- A regression check must reject unconditional main-queue deferral inside requested horizontal scrolling.
- Verify the local `isSelected` tab animation and the explicit keyboard scroll animation remain present.
- Run a macOS Debug clean build after changing scroll timing.

### 7. Wrong vs Correct

#### Wrong

```swift
withAnimation(.spring()) {
    viewModel.showSmartFilter(type)
}

DispatchQueue.main.async {
    proxy.scrollTo(itemID, anchor: .center)
}
```

#### Correct

```swift
viewModel.showSmartFilter(type)

if animated {
    withAnimation(.easeInOut(duration: 0.12)) {
        proxy.scrollTo(itemID, anchor: .center)
    }
} else {
    proxy.scrollTo(itemID, anchor: .center)
}
```

## Scenario: Database-supplemented clipboard search

### 1. Scope / Trigger

Use this contract when an active search combines the bounded in-memory history window with matching records fetched directly from SwiftData.

### 2. Signatures

```swift
nonisolated static func uniqueAppendIndexes(
    existing: [ClipboardItemDeduplicationKey],
    incoming: [ClipboardItemDeduplicationKey]
) -> [Int]

private func applyDisplayedItemIDsIfChanged(_ newIDs: [UUID])
```

### 3. Contracts

- Deduplicate supplemental records against the complete in-memory item collection by both persistent ID and `contentHash`, not only against currently visible IDs.
- Apply the same ID-and-hash rule within one supplemental database page.
- Append only IDs belonging to items that were accepted for insertion into `items`; every `displayedItemIDs` entry must resolve through `item(for:)`.
- Treat an unchanged ordered ID sequence as a no-op. Do not publish it or reconcile selection again.
- Keep supplement filtering and merge policy in the ViewModel/model layer. Views receive a stable ordered item sequence.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Database result has an existing UUID | Reject it |
| Database result has a new UUID but an existing content hash | Reject it without mutating `items` |
| Two results in one page share a content hash | Accept only the first result |
| Supplemental result is unique | Merge it, then publish its resolvable ID once |
| Refilter produces the current ordered IDs | Do not publish another list change |
| Query or scope changes while SQL search is running | Discard the stale generation |

### 5. Good / Base / Bad Cases

- Good: the supplemental merge accepts only new ID/hash pairs and publishes one stable combined result.
- Base: SQL returns no records outside the memory window and no list mutation occurs.
- Bad: append every SQL result ID before `mergeItems` performs content-hash deduplication.
- Bad: assign an equal `displayedItemIDs` array on every `$items` emission.

### 6. Tests Required

- A policy regression test must cover a new UUID with an existing content hash.
- The same test must cover duplicate IDs and duplicate hashes within the incoming page.
- Run a macOS Debug build after changing the search supplement pipeline.

### 7. Wrong vs Correct

#### Wrong

```swift
mergeItems(dbResults, prepend: false)
displayedItemIDs.append(contentsOf: dbResults.map(\.id))
```

#### Correct

```swift
let acceptedIndexes = ClipboardItemDeduplicationPolicy.uniqueAppendIndexes(
    existing: existingKeys,
    incoming: candidateKeys
)
let newItems = acceptedIndexes.map { scopedResults[$0] }
mergeItems(newItems, prepend: false)
applyDisplayedItemIDsIfChanged(visibleIDs + newItems.map(\.id))
```
