# Group Switch Horizontal Bounce Implementation Plan

## Red

- [x] Add and run a source-boundary regression script proving group scope changes still use broad `withAnimation` and requested scrolls still use unconditional main-queue deferral.

## Green

- [x] Remove broad group-switch animation wrappers while preserving local tab animations.
- [x] Execute `listScrollRequest` scrolling in the current SwiftUI update cycle.
- [x] Defer only initial on-appear positioning by one `MainActor` yield.

## Verification

- [x] Run the regression script and confirm it passes.
- [x] Confirm keyboard scroll requests retain their explicit animation branch.
- [x] Run `git diff --check`.
- [x] Run macOS arm64 Debug clean build.
