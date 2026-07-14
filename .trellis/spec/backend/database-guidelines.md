# Database Guidelines

## Scenario: SwiftData snapshots under MainActor-by-default

### 1. Scope / Trigger

Use this contract when a SwiftData `@ModelActor` maps `@Model` records into immutable values that leave the store actor. The project enables `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so otherwise-unannotated helper value types are implicitly main-actor isolated.

### 2. Signatures

```swift
private nonisolated struct RecordSnapshot: Sendable {
    static func makeFromRecord(_ record: Record) -> RecordSnapshot
}

@ModelActor
actor RecordSearcher {
    func fetchSnapshots() async -> [RecordSnapshot]
}
```

### 3. Contracts

- Fetch and read every SwiftData `@Model` instance only inside the `@ModelActor` that owns its `ModelContext`.
- Snapshot values that cross out of the store actor must be immutable and `Sendable`.
- Declare a pure snapshot type `nonisolated` when its factory is called from a non-main `@ModelActor`; this opts the value conversion out of the project's implicit MainActor isolation.
- Do not mark the SwiftData model `Sendable` or pass it to another actor. Only the completed snapshot crosses the actor boundary.
- Snapshot factories must not touch `@Attribute(.externalStorage)` values when concurrent store writes can invalidate their backing files.

### 4. Validation & Error Matrix

| Condition | Required behavior |
| --- | --- |
| Snapshot factory is implicitly MainActor-isolated | Build must fail the warning regression for a `@ModelActor` call site |
| Store actor fetch returns no record | Return `nil` or an empty snapshot list without crossing a model instance |
| Snapshot contains a non-Sendable field | Keep the value inside the actor or convert it to a Sendable representation |
| External-storage blob is unavailable | Omit it from the lightweight snapshot and load it later through a fresh store-actor fetch |

### 5. Good / Base / Bad Cases

- Good: the model actor reads regular columns, creates a `nonisolated Sendable` snapshot synchronously, then returns the snapshot.
- Base: an empty fetch returns no snapshots.
- Bad: wrapping snapshot conversion in `MainActor.run`, which sends the live SwiftData model to the wrong actor.
- Bad: adding `@unchecked Sendable` to a SwiftData model to silence diagnostics.

### 6. Tests Required

- A clean macOS build must contain no `main actor-isolated static method` diagnostic for snapshot factories.
- Store/search tests must verify snapshot mapping still preserves identifiers, content type, source metadata, and truncated preview text.
- Concurrency changes must be verified with the project's normal build settings, including MainActor-by-default.

### 7. Wrong vs Correct

#### Wrong

```swift
private struct RecordSnapshot: Sendable {
    static func makeFromRecord(_ record: Record) -> Self { /* ... */ }
}

@ModelActor
actor Searcher {
    func fetch() -> RecordSnapshot {
        RecordSnapshot.makeFromRecord(record)
    }
}
```

The snapshot factory is implicitly MainActor-isolated and conflicts with the model actor.

#### Correct

```swift
private nonisolated struct RecordSnapshot: Sendable {
    static func makeFromRecord(_ record: Record) -> Self { /* ... */ }
}
```

The factory executes synchronously in the caller's actor context, while only the immutable snapshot leaves that actor.
