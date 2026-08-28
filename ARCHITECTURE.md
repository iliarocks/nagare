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

The application data flow is the reference vertical slice:

```text
SwiftUI -- ID-addressed command --> NagareDataStore
                                        |
                              NagareDataOrchestrator
                               /                 \
                    pure deterministic plan   persistence port
                                               |
                                  SwiftDataNagareRepository
                                               |
                                fresh short-lived ModelContext
                                               |
                                           SwiftData
```

Sync reconciliation follows the same shape:

```text
HistoryObserver / app activation
              |
SyncReconciliationOrchestrator -- SyncReconciliationPersistence (port)
              |                                  |
SyncReconciliationPlanner (pure)   SwiftDataSyncReconciliationAdapter
              |                                  |
immutable graph + explicit plan             SwiftData / CloudKit
```

Live reads cross one strict value boundary. `SwiftDataNagareRepository` creates
a new short-lived `ModelContext` for each load, maps the complete persisted
graph to `NagareDataSnapshot`, and releases every managed object before the
value reaches the application layer. `NagareDataStore` publishes that one
immutable graph. Persistent-history events trigger reconciliation in another
fresh context, followed by a fresh snapshot load. No managed object is UI
state, and features may not introduce `@Query`, `ResultsObserver`, or direct
SwiftData access.

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
- Orchestrators own use-case sequencing; persistence adapters own their single
  transaction and roll it back before propagating an I/O failure.
- UI code retains semantic IDs and immutable values only. All reads and writes
  cross application ports. SwiftData is limited to Infrastructure plus the App
  composition root and persistent-history bridge that construct those adapters.

## Persistence and sync

Nagare has one persisted model and one transaction path. SwiftData remains the
local source of truth; CloudKit replicates that store's records through the
user's private database. There is no second "cloud DTO" graph to translate,
version independently, or accidentally let drift from the local graph.

iCloud is an explicit user preference and defaults to off. Startup always
passes either `.private(...)` or `.none` to `ModelConfiguration`; capabilities
alone never decide whether a person's store syncs. A preference change retires
the current runtime before opening the replacement, so only one stack ever has
the SQLite store open. If the replacement fails, Nagare reopens the prior
configuration and leaves the saved preference unchanged.

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
3. `SyncIntegrityMonitor` owns continuous persistent-history observation.
   History publishes a fresh immutable snapshot immediately; a completed
   CloudKit import separately debounces reconciliation. Observation, repair,
   and partial-import failures retry indefinitely with a capped backoff, and
   every repair uses a fresh context. No view lifecycle keeps data correct,
   and a repair rollback can never discard an in-progress UI transaction.
4. `SyncReconciliationPlanner` receives one immutable graph and returns an
   explicit deterministic plan. Missing relationship edges are pending import
   states. It never reads SwiftData identity or performs I/O.
5. `SwiftDataSyncReconciliationAdapter` translates records, applies the plan,
   and saves atomically. It contains no conflict or recurrence policy.

The repair rules are idempotent and preserve records when a related CloudKit
record may still be in flight. The same complete input therefore converges to
the same result on every device.

A migrated V1 record without a physical identity deterministically uses its
semantic UUID. Random IDs and store-local persistent identifiers are forbidden
as replicated conflict tie-breakers. A local token may choose between records
only after every replicated field is equal, when either deletion produces the
same replicated result.

Reconciliation writes preserve existing `modifiedAt` values. Assigning a
physical identity, reconnecting a relationship, or removing a duplicate is not
a user edit and must never make an old record win a later content conflict.

Virtual recurrence projection consumes an immutable graph of every template
and occurrence fetched independently. It identifies the current item by
semantic ID and sequence even before CloudKit imports the inverse relationship.
A template imported before its current occurrence is skipped as pending; it
never empties unrelated projections or turns a reorder into a save failure.

Published snapshot indexes use the same canonical replicated-record ordering
as reconciliation. A duplicate that is visible during a partial import is
therefore one deterministic read value rather than a trapping dictionary
initializer; the history-driven repair still removes the redundant record.

All future persisted-model changes must keep the CloudKit contract:

- no database uniqueness constraints;
- every nonoptional attribute has a schema-level default;
- relationships are optional, have explicit inverses, and do not deny deletes;
- migrations are additive, with a new frozen `VersionedSchema` for every
  released shape;
- all writes go through `SwiftDataTransaction`.

See `SYNC_AND_MACOS.md` for conflict behavior, platform design, and the release
checklist.
