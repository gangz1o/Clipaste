# Fix link metadata stall regression

## Goal

Eliminate the CPU and memory regression introduced by byte-at-a-time link metadata streaming while preserving the hard network-transfer limits added in v2.2.8.

## Requirements

- HTML and favicon bodies must still be rejected before download when a declared content length exceeds the configured limit.
- Unknown or incorrect content lengths must be cancelled as soon as a received data chunk would exceed the configured limit.
- Automatic link metadata work must have a small global concurrency limit and waiting work must remain cancellable during shutdown.
- Rich/default link display behavior and local syntax highlighting behavior must remain unchanged.
- Source applications that cannot provide a real declared icon must display the Clipaste app icon instead of Safari or the macOS generic application placeholder.
- Do not add dependencies or alter persisted clipboard data; keep changes within the metadata transport, shared source-icon rendering boundary, and regression coverage.

## Acceptance Criteria

- [x] Link metadata response bodies are consumed in data chunks rather than one async suspension per byte.
- [x] Existing valid metadata, MIME validation, byte limits, candidate limits, opt-out, and cancellation tests pass.
- [x] A concurrent regression test proves no more than four metadata fetches enter the transport simultaneously.
- [x] A 24-by-512-KiB local stress probe no longer exhibits the byte-iterator instruction explosion.
- [x] Strict-concurrency type checking and the full macOS Debug build pass.
- [x] Missing, unknown, and iconless source applications fall back to the Clipaste app icon while normal application icons remain unchanged.

## Notes

- Diagnosis on 2026-08-13 reproduced roughly 14.7 billion retired instructions for 24 concurrent 512-KiB responses versus roughly 78 million using chunk delivery.
- A system memory-pressure report recorded Clipaste around 441 MiB resident with a lifetime peak around 652 MiB; no conventional Clipaste crash report was present.
