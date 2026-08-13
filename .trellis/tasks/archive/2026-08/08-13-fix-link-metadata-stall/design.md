# Design: Fix link metadata stall regression

## Root cause

`URLSession.AsyncBytes` exposes individual bytes. The v2.2.8 hard-limit loop therefore performs up to 524,288 async iterator steps for one HTML response and up to 262,144 for each favicon. History hydration can enqueue 24 missing links at once, multiplying scheduling, allocation, and CPU cost even though transfer size is bounded.

## Transport boundary

Replace byte iteration with a small `URLSessionDataDelegate` adapter that:

1. receives response headers before body data;
2. validates status, final URL, MIME type, and declared size;
3. accumulates `didReceive data` chunks only while the total remains within the hard limit;
4. cancels and completes exactly once when a chunk would exceed the limit;
5. exposes one async result and propagates Swift task cancellation to the underlying data task.

The adapter creates a session from the injected session configuration so the existing mock `URLProtocol` tests remain deterministic. The session is explicitly invalidated after the page and favicon sequence to break the URLSession/delegate ownership cycle.

## Concurrency boundary

A cancellation-aware actor grants four global metadata permits. One permit covers the complete page/title/favicon sequence. Cancelled waiters are removed and resumed, so `StorageManager.shutdown()` cannot wait forever on a queued metadata task.

## Compatibility and rollback

- Public call sites and stored metadata stay unchanged.
- Existing byte and icon-candidate limits stay unchanged.
- The change is isolated to `LinkMetadataEngine` plus its standalone regression harness.
- Rollback is one commit; no persisted-data migration is required.
