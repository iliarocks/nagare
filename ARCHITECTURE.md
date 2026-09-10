# Architecture

Nagare is a SwiftUI task list for iPhone and Mac. Shared behavior lives in value
models and planning functions; platform views and persistence stay at the edges.

| Folder | Responsibility |
|---|---|
| `Nagare/Domain` | Immutable snapshots, recurrence, ordering and conflict rules. Foundation only. |
| `Nagare/Application` | Commands and persistence interfaces. Foundation only. |
| `Nagare/Infrastructure` | SwiftData records, transactions, history and CloudKit integration. |
| `Nagare/App` | Composition, lifecycle and the observable data store. |
| `Nagare/Features` | Screens and shared presentation components. No managed objects. |

`NagareDataStore` sends commands through `NagareDataOrchestrator`.
`SwiftDataNagareRepository` creates a context for each operation, translates
records to immutable snapshots, and commits writes through `SwiftDataTransaction`.
Views receive a fresh snapshot after a successful operation. Failed writes do not
publish partial state. Sorting within a list uses the shared `OrderingPlanner`;
item, project and project-item moves use the same command path as the UI.

Recurrence and project-membership workflows allocate positions inside their
existing transaction using `SwiftDataOrderAllocation`. Allocation does not save.
There is no second compatibility API for performing drag-and-drop writes.

`Features/Shared` groups list interaction, document editing, editor toolbars,
modal presentation and platform styling by responsibility. iOS and macOS keep
native controls where their interaction differs.

## Persistence and sync

The current SwiftData schema is version 5. There is no explicit migration plan
or retained V1/V2 model implementation. Compatible changes rely on SwiftData's
automatic migration; compatibility must be tested, not inferred from a schema
version number. The upgrade test opens a frozen, synthetic pre-cleanup database.
Keep legacy `Event` and inherited record shapes while they remain part of stored
data. Do not remove persisted models as ordinary dead-code cleanup.

The optional iCloud connection uses the private database in
`iCloud.ilia.page.nagare`. Development signing selects CloudKit development;
App Store signing selects production. Sync preference changes apply at the next
launch, keeping one persistence stack alive for the process lifetime.

`SyncIntegrityMonitor` observes persistent history. Pure reconciliation plans
resolve duplicate identities and recurrence state, and the SwiftData adapter
applies each plan transactionally. Logical IDs and physical record identities
are distinct so CloudKit conflicts can be reconciled deterministically.

`Scripts/lint-imports.sh` enforces dependency and transaction boundaries.
Build, test and release instructions are in [DEVELOPMENT.md](DEVELOPMENT.md).
