# Implementation plan

1. Replace `AsyncBytes` body iteration with a chunked delegate adapter.
   - Verify valid, oversized, wrong-MIME, and cancellation paths in `LinkMetadataTrafficTests`.
2. Add a cancellation-aware four-permit metadata limiter.
   - Verify a concurrent mock workload never exceeds four active page requests.
3. Add performance-focused regression coverage and update the remote-enrichment spec.
   - Verify the stress probe instruction count is near chunked `data(for:)` behavior rather than the v2.2.8 byte iterator.
4. Run strict-concurrency type checking, repeated standalone tests, full macOS Debug build, and `git diff --check`.
5. Review only the task diff and preserve all unrelated repository state.
6. Replace generic source-app icon placeholders with the bundled Clipaste icon at the shared `AppIconView` boundary.
   - Verify missing/unknown bundle IDs and iconless system apps use Clipaste while Chrome and other declared icons remain unchanged.

## Verification results

- Standalone traffic/concurrency/cancellation suite passed 10 consecutive runs.
- Strict-concurrency type checking completed with no diagnostics.
- Full macOS Debug build succeeded; the only emitted warning was Xcode selecting arm64 from two matching local destinations.
- The 24-by-512-KiB stress probe fell from approximately 14.7 billion to 1.2 billion retired instructions, from 203 ms to 27 ms measured work time, and from roughly 56 MiB to 15.5 MiB peak footprint.
- `git diff --check` and Trellis task validation passed.
- An `ImageRenderer` harness verified missing source IDs and `com.apple.loginwindow` render the Clipaste icon, while `com.google.Chrome` retains its real icon. The built app contains `AppIcon.icns` and AppIcon asset renditions.
