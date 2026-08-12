# Nagare architecture

Nagare uses four inward-facing layers. Dependencies point down this list and
never back up:

1. **Domain** contains immutable value snapshots and pure deterministic logic.
   It imports Foundation only and has no clock, database, UI, or shared-defaults
   access. Callers pass dates and calendars explicitly.
2. **Application** contains orchestrators and I/O port protocols. An
   orchestrator laminates snapshots, one or more pure plans, and a port into an
   atomic use case. It imports Foundation only.
3. **Infrastructure** contains SwiftData records, shared-defaults stores, and
   concrete port adapters. Adapters translate records to snapshots and apply
   explicit change sets; they do not decide policy.
4. **Features/App/AppIntents/Widgets** are delivery mechanisms. They render
   state, collect user input, and invoke a facade or orchestrator.

The ordering flow is the reference vertical slice:

```text
SwiftUI / App Intent
        |
compatibility facade
        |
ItemOrderingOrchestrator ---- ItemOrderingPersistence (port)
        |                              |
OrderingPlanner (pure)       SwiftDataOrderingAdapter
        |                              |
immutable snapshots                 SwiftData
```

`Scripts/lint-imports.sh` enforces framework allowlists for each inner layer,
rejects side-effect APIs in Domain/Application, and rejects direct
`ModelContext.save()` calls outside Infrastructure. The Xcode app target runs
the linter before compilation.

## Design rules

- Domain model stored properties are `let`; mutable SwiftData classes are
  persistence records, not domain models.
- Pure functions receive time, calendar, and other environmental inputs as
  parameters. They return a value, plan, or explicit change set.
- I/O adapters are intentionally boring: load, translate, apply, save, and
  rollback.
- Orchestrators own transaction order and always roll back before propagating
  an I/O failure.
- UI code must not call `ModelContext.save()` directly. Existing record-editing
  screens use `SwiftDataTransaction` while their larger workflows are migrated
  behind ports.

## Persistence and sync

Nagare has one persisted model and one transaction path. SwiftData remains the
local source of truth; CloudKit replicates that store's records through the
user's private database. There is no second "cloud DTO" graph to translate,
version independently, or accidentally let drift from the local graph.

iCloud is an explicit user preference and defaults to off. Startup always
passes either `.private(...)` or `.none` to `ModelConfiguration`; capabilities
alone never decide whether a person's store syncs. A preference change applies
on the next launch so only one stack ever has the SQLite store open.

`NagareSchemaV1` is the frozen model shipped before sync. `NagareSchemaV2` is
the first CloudKit-compatible model, and `NagareMigrationPlan` owns the
additive migration between them. Historical schemas are immutable once
released.

CloudKit cannot enforce the old SQLite uniqueness constraints while records
are imported asynchronously. Semantic UUID identity is therefore an
application invariant:

1. Every record has a replicated physical `syncRecordID`, distinct from its
   semantic UUID, so exact timestamp ties have a device-independent survivor.
2. `SwiftDataTransaction` stamps every changed record's `modifiedAt` and is the
   only production save boundary.
3. `SyncIntegrityMonitor` observes persistent-history changes and debounces a
   reconciliation pass after imports.
4. `SyncIntegrityRepair` deterministically selects one canonical record for a
   duplicated UUID, reconnects relationships, and repairs concurrent
   recurrence successors in a single transaction.

The repair rules are idempotent and preserve records when a related CloudKit
record may still be in flight. The same complete input therefore converges to
the same result on every device.

All future persisted-model changes must keep the CloudKit contract:

- no database uniqueness constraints;
- every nonoptional attribute has a schema-level default;
- relationships are optional, have explicit inverses, and do not deny deletes;
- migrations are additive, with a new frozen `VersionedSchema` for every
  released shape;
- all writes go through `SwiftDataTransaction`.

See `SYNC_AND_MACOS.md` for conflict behavior, platform design, and the release
checklist.
