# Group Switch Horizontal Bounce Design

## State Flow

`group action -> scope state -> async displayed IDs -> reset selection -> listScrollRequest -> ScrollViewProxy.scrollTo`

The visible bounce comes from applying a broad spring transaction at the start while deferring the final scroll operation to another main-loop turn. The fix keeps selection-style animation local to `MinimalGroupTabButton` and aligns the programmatic scroll with the `listScrollRequest` view update.

## Changes

- Replace the four header group-selection `withAnimation` wrappers with direct ViewModel intent calls. `MinimalGroupTabButton` already animates `isSelected` and `isHovered` independently.
- Make `ClipboardHorizontalView` execute `listScrollRequest` immediately from its `onChange` callback.
- Keep initial on-appear positioning deferred by one `MainActor` yield because the lazy stack still needs its first layout pass.
- Keep `animated == true` scroll requests wrapped in the existing 0.12-second ease-in-out animation.

## Compatibility

The filtered item identities, first-item selection, scroll anchor, quick-paste frame tracking, keyboard navigation, and vertical layout behavior remain unchanged.
