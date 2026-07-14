# macOS SwiftUI Feature Boundaries

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
