# Logging Guidelines

## Scenario: Privacy-safe runtime diagnostics

### Contracts

- Use `os.Logger` with the application bundle identifier and a narrow category such as `storage`, `clipboard-resource`, `link-metadata`, or `ai-security`.
- Log state transitions and bounded failure facts, not user content. Useful fields include route kind, operation name, record count, byte count, retry attempt, HTTP status, and a stable internal error category.
- Use `debug` for development-only scheduling details, `info` for successful lifecycle transitions, `notice` for policy rejection or degraded fallback, and `error` for an operation that failed and needs attention.
- Repeated automatic failures must be deduplicated or bounded. Retry bookkeeping may not grow without limit or emit an unbounded stream of identical messages.
- Prefer content-free messages. If interpolation is necessary, explicitly mark only non-sensitive aggregate values as public.

### Never Log

- Clipboard text, HTML, RTF, image data, OCR text, filenames copied by the user, or source application document contents.
- Full URLs, hosts derived from clipboard content, query strings, redirect targets, response bodies, page titles, or favicon bytes.
- AI API keys, authorization headers, prompts, model responses, Keychain payloads, or legacy credential JSON.
- SwiftData external-storage blobs or exported record payloads.

### Validation Matrix

| Event | Safe diagnostic |
| --- | --- |
| Image exceeds resource budget | Resource kind plus configured byte/pixel limit |
| Link target fails network policy | Policy reason category only; omit the URL and host |
| Storage route fallback | Source/target route kinds and failure category |
| Metadata retry exhausts attempts | Attempt count and operation category |
| Keychain operation fails | Operation (`read`, `write`, `delete`) and OSStatus category; never account/key/value |

### Tests Required

- Source checks reject logging of credential fields, clipboard bodies, and full link targets in automatic enrichment paths.
- Failure-path tests assert retries and in-flight markers are bounded even when every operation fails.
- Review Console output while exercising a rejected private-network URL and an oversized image; no user-derived content may appear.
