# Frontend Directory Structure

## Layout

```text
clipaste/
├── Views/       # SwiftUI screens, reusable subviews, and narrow AppKit bridges
├── ViewModels/  # @MainActor observable state and user-intent orchestration
└── Models/      # Immutable UI DTOs and presentation policies
```

## Module Boundaries

- The primary `Type.swift` file owns the type declaration, stored UI state, and the smallest useful rendering entry point.
- Split additional behavior by responsibility as `Type+Concern.swift`, for example `ClipboardMainView+Focus.swift` or `ClipboardViewModel+HistoryLoading.swift`.
- Extract independently renderable regions into named subviews instead of growing one screen body indefinitely.
- An extracted View must receive state or intents from its owner; it must not create a second source of truth for the same feature.
- AppKit representables and window observers live in dedicated files when they own platform lifecycle behavior.

## Size Guard

- Every hand-written Swift file under `clipaste/` and `scripts/` must stay at or below 300 physical lines.
- Split at behavior, lifecycle, rendering, or platform boundaries before shortening names or compressing formatting.
- Exceptions are allowed only when the code cannot be split safely and must be documented in `scripts/SwiftFileSizeTests.swift` with a concrete reason. The default exception list is empty.

## Naming

- Use `Type+Concern.swift` for cross-file extensions of one owner.
- Use the extracted component or bridge type as the filename for standalone types.
- Avoid generic names such as `Helpers.swift`; the filename must reveal the responsibility.

## Examples

- `ClipboardHeaderView.swift` owns header state and the rendering entry point; layout, group tabs, overflow, controls, and drop handling are separate concern files.
- `ClipboardCardView+Content.swift` owns card-specific content rendering while the primary file owns card state and selection styling.
- `SettingsWindowObserver.swift` and `WindowAppearanceObserver.swift` isolate distinct AppKit window responsibilities.
