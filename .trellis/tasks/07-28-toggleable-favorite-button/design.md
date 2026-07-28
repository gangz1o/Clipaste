# Hover Favorite Button Design

## Architecture and Boundaries

- Add one reusable SwiftUI presentation component for the favorite control. It receives `isFavorite`, the current accent color, and an action closure; it owns no persistence or clipboard business logic.
- `ClipboardCardView` renders the control in a bottom-leading overlay for horizontal cards.
- `ClipboardVerticalItemView` renders the same control in the existing non-compact inline-action area.
- Both views forward the action to the existing `ClipboardViewModel.pinItem(item:)`; `ClipboardViewModel.setFavoriteState` remains the only owner of in-memory and persistent favorite changes.
- No new shared state, ViewModel, setting, or dependency is introduced.

## Visibility Contract

The control is rendered only when the item is hovered or selected and the quick-paste modifier is not held. Compact vertical layout remains unchanged. Horizontal AI and quick-paste accessories retain their existing bottom-trailing placement and precedence.

## Interaction Contract

- Unfavorited items use an outlined star; favorited items use a filled star.
- Favorited and pressed feedback use `AppAccentColor.color`; changing the theme updates the control through the existing `@AppStorage` observation in each item view.
- Before toggling, the control calls the existing one-shot paste suppression hook so clicking it cannot trigger single-click paste through the card's ancestor simultaneous gesture.
- When single-click paste is enabled, the control forwards the normal primary-selection update before suppression; an unconsumed suppression marker expires after the current input event so later keyboard or accessibility pastes are unaffected.
- The control exposes localized help and accessibility labels using the existing `Add to Favorites` and `Remove from Favorites` String Catalog keys.

## Performance

The reusable control is a value-type SwiftUI view with no asynchronous work, no per-item persistence lookup, and no new observation source. It is only inserted for hovered or selected rows, keeping the ten-thousand-plus item rendering path unchanged for inactive items.

## Compatibility and Rollback

- Existing favorite data and persistence format are unchanged.
- Existing AI, quick-paste, drag, context-menu, and selection contracts remain intact.
- Rollback consists only of removing the shared control and its two presentation call sites.
