# Error Handling

## Scenario: Recoverable startup, route, and credential failures

### Contracts

- Opening the preferred SwiftData route is recoverable. Fall back to the local route, then to an in-memory runtime, while publishing a diagnostic that the UI can surface.
- Never terminate the app because a persistent store cannot open or because no `NSScreen` is currently available. A missing screen skips presentation; an unusable persistent route keeps the in-memory runtime alive.
- A route transition is transactional at the runtime level: drain the source, prepare and drain the target, merge, then activate. If preparation or merge fails, keep the previous route active and report the error.
- Errors that cross from a store actor, network actor, or detached image task are converted to immutable values or localized user-visible messages before MainActor publication.
- Keychain persistence is authoritative for AI credentials. Write or delete the Keychain value before updating non-secret configuration metadata.
- Legacy plaintext credential migration clears the value from `UserDefaults` only after every required Keychain write succeeds. On partial failure, preserve the legacy payload so a later launch can retry without losing access.
- Cancellation is not presented as a product error. Propagate it through worker tasks, clean up in-flight state, and suppress stale UI publication.

### Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Preferred cloud route fails to open | Try local, report degraded mode, keep the app usable |
| Local route also fails | Start an in-memory runtime and report that persistence is unavailable |
| Route merge fails | Retain the previous active runtime and leave the requested route uncommitted |
| Keychain write fails while saving | Keep the previous configuration and show a save error |
| Keychain delete fails | Keep the configuration entry so its credential is not orphaned silently |
| Legacy credential migration partially fails | Keep the legacy JSON unchanged and retry later |
| Screen lookup returns no display | Return without creating or positioning a panel |
| Task is cancelled | Release permits/in-flight markers and do not publish an error banner |

### Tests Required

- Inject startup factories that fail preferred and local routes and assert the in-memory fallback is selected.
- Inject transition participants and assert drain/activation order plus rollback on failure.
- Inject a credential store and test successful migration, partial failure, save failure, and delete failure.
- Run the app build with complete strict-concurrency warnings enabled.

### Common Mistakes

- Calling `fatalError` or force-unwrapping `NSScreen.main` on a normal recoverable path.
- Replacing the active store before its target has opened, drained, and completed its merge.
- Removing a configuration after its Keychain deletion failed.
- Clearing legacy plaintext before all credentials are durably stored.
- Converting cancellation into a retry or user-visible failure.
