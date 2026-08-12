# Nagare sync and macOS

## Architecture decision

Nagare does not maintain a simplified parallel data structure in iCloud.
That approach would introduce a second schema, bidirectional translation,
partial-failure states, and a new conflict system while discarding the
relationships SwiftData and CloudKit already know how to replicate.

The app instead uses a single normalized SwiftData graph on every device.
CloudKit mirrors the records in the user's private database, and each device
reconstructs its local SQLite store through the framework's normal import
process. Offline operation remains local-first.

```text
iPhone SwiftUI ---- SwiftData store ----+
                                        |
                             private CloudKit database
                                        |
Mac SwiftUI ------- SwiftData store ----+
```

Both platforms use the same model, migration plan, transaction boundary,
container identifier, and application logic. Their presentation differs:
iOS keeps the tab interface; macOS uses a native sidebar/detail layout,
standard menus, keyboard shortcuts, a Settings scene, and AppKit sharing.

iCloud sync is off by default. The Settings screen is the single home for
Completed history, the sync preference, and future privacy/import/export
features. Enabling or disabling sync changes the configuration used on the
next launch; Nagare never opens simultaneous local-only and CloudKit stacks on
the same store. Disabling sync preserves the local database and stops future
replication on that device, but does not claim to delete the user's existing
private CloudKit copy.

## Schema evolution

`NagareSchemaV1` is an exact frozen copy of the original on-device schema.
`NagareSchemaV2` is the first syncable schema. Its differences are deliberate:

- UUIDs are indexed semantic identities rather than store-level unique
  constraints.
- Every required CloudKit field has a schema-level default.
- To-many relationships use optional persisted storage and nonoptional
  read-only facades for the rest of the app.
- Every relationship has an explicit inverse and a CloudKit-safe delete rule.
- `modifiedAt` and the physical `syncRecordID` were added as optional metadata,
  so migration is additive and old records remain intact. Repair assigns a
  stable physical identity once before a migrated record is exported.

Never edit a released schema enum. Add a new `VersionedSchema`, append a stage
to `NagareMigrationPlan`, and test both an upgrade store and a fresh store.
CloudKit production schemas are also additive; deployed fields and record
types should be treated as permanent.

## Transactions and conflicts

`SwiftDataTransaction` is the sole production save path. It gives every
inserted or changed sync record one transaction timestamp, saves atomically,
and rolls the context back on failure. The import linter rejects new direct
`ModelContext.save()` calls elsewhere.

CloudKit imports are eventually consistent and may briefly expose only one
side of a relationship. `SyncIntegrityMonitor` debounces persistent-history
events before asking `SyncIntegrityRepair` to restore semantic invariants.
The repair also runs at launch and whenever the app becomes active.

Conflict rules are deterministic:

- Duplicate semantic UUIDs keep the greatest `modifiedAt`, falling back to
  `createdAt` and then the replicated `syncRecordID`. Project and recurrence
  relationships are moved to the canonical record before deletion.
- Competing todo successors keep the occurrence named by the template when it
  is available; otherwise they use the same deterministic record ordering.
  Earlier occurrences remain as completed history.
- Event recurrences keep the highest available sequence and update the
  template pointer to it.
- If the template points beyond the records currently imported, or if a
  future client introduces an unknown item kind, the older client waits and
  does not rewrite data it cannot understand.

These policies prioritize convergence without converting a temporary partial
import into permanent data loss.

## CloudKit environments

The shared container is `iCloud.ilia.page.nagare`. Development-signed builds
use CloudKit's development environment; distribution builds use production.
The two databases are isolated even though the container identifier is the
same. Debug and release builds also use separate bundle identifiers and app
groups.

The app remains usable offline or while account status cannot be determined.
Settings explains whether data is local-only or expected to replicate to the
user's other devices; low-level iCloud account state is intentionally not
presented as user-facing status.
Framework import/export failures are retried by the persistent CloudKit stack;
semantic repair failures are nonfatal and retry on the next history event,
foreground activation, or launch.

### Resolved development finding: `VIRTUAL-001`

Two-device testing exposed an eventual-consistency edge case after the initial
import. A recurrence template can become visible before the occurrence named by
its `currentItemID`. Reordering is one way to refresh Upcoming while the graph
is in that partial state, so it surfaces `VIRTUAL-001`; this does not imply that
the ordering transaction itself is invalid.

The architecture now handles this without inventing an occurrence, clearing
the pointer, or deleting the template:

- projection consumes immutable snapshots of all templates and occurrences;
- current identity and sequence work before an inverse relationship edge;
- an unresolved current occurrence is a nonfatal pending projection;
- persistent-history observation retries reconciliation outside the UI; and
- planner and SwiftData integration tests cover import-order permutations,
  missing relationship edges, conflict convergence, and idempotence.

The development schema still must not be promoted until the full physical
two-device matrix below passes. Automated partial-import coverage removes the
known `VIRTUAL-001` architecture defect; it does not substitute for CloudKit
transport testing on real devices.

In a development-signed build, pass `--initialize-cloudkit-schema` once after
an intentional model change. The debug-only initializer derives the managed
object model from `NagareSchema.current`, initializes the development
environment through `NSPersistentCloudKitContainer`, unloads that container,
and deletes its disposable local store before the normal SwiftData stack
opens. It never runs during ordinary launches or in release builds.

## Release checklist

Do not ship solely because both targets compile. Complete this sequence:

1. Archive a copy of an existing production iOS store, install an upgrade
   build over it, and verify item values, ordering, projects, completion
   history, and recurrences.
2. Enable iCloud in Nagare Settings and relaunch both test devices. Sign into
   the same test iCloud account on an iPhone and a Mac. Exercise
   create, edit, move, reorder, complete, delete, and recurrence advancement
   in both directions, including offline edits followed by reconnection.
3. Run a development build once with `--initialize-cloudkit-schema`. In
   CloudKit Console, inspect the development record types and verify import and
   export logs are clean after the two-device matrix.
4. Deploy the validated development schema to production. Do not make manual
   production-only schema edits.
5. Test the production environment with an internal distribution build using
   both a fresh account and an account upgraded from the existing iOS app.
6. Take a pre-release device backup, retain the prior build, and use a staged
   rollout while monitoring store-open and CloudKit errors.

The automated gates are `Scripts/lint-imports.sh`, the full `NagareTests`
suite on the macOS host, an iOS `build-for-testing`, and signed builds of both
platform products. Migration tests cover both a versioned V1 fixture and the
original unversioned store construction used by the released app.
