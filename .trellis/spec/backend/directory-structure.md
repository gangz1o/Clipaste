# Backend Directory Structure

## Layout

```text
clipaste/
├── Managers/   # Runtime facades, storage actors, capture, and AppKit coordinators
├── Services/   # Stateless policies, migrations, network, AI, and transfer workflows
├── Models/     # Domain values shared across actors and layers
└── Utilities/  # Low-level bounded file and image primitives
```

## Module Boundaries

- Keep public call surfaces in the primary facade file and place lifecycle, commands, queries, transfer, maintenance, and mapping in named concern files.
- A SwiftData actor owns model access. Cross-file actor extensions may share internal implementation state, but callers continue through the facade rather than reaching into actor helpers.
- Put pure, injectable decisions in `Services/` so deterministic script tests can compile them without the whole app.
- Network transport adapters, concurrency limiters, destination policies, and response models are separate responsibilities even when one feature composes them.
- Migration sources use one file per external schema plus shared routing, timestamp, string, and SQLite helpers.

## Size Guard

- Every hand-written Swift file under `clipaste/` and `scripts/` must stay at or below 300 physical lines.
- Split at data ownership and lifecycle boundaries; do not evade the guard with dense formatting or unrelated generic helper bags.
- Any unavoidable exception must be explicit and justified in `scripts/SwiftFileSizeTests.swift`. The project currently has no exceptions.

## Naming

- Use `Type+Concern.swift` when behavior remains owned by one facade or actor.
- Name standalone policies and adapters for the contract they own, such as `LinkMetadataNetworkPolicy.swift` or `OCRFallbackCoordinator.swift`.
- Test support shared by one script suite uses the matching `*TestSupport.swift` name.

## Examples

- `StorageManager.swift` is the facade; lifecycle, history queries, record commands, group commands, and mapping are separate files.
- `ClipboardStoreActor.swift` owns the model context; loaders, commands, transfer, duplicate maintenance, and content maintenance are separate actor extensions.
- `ClipboardRuntimeStore.swift` owns runtime state; bootstrap, route transition, cloud reset, diagnostics, synchronization, and maintenance are separate concern files.
