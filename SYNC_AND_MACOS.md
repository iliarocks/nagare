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
features. Enabling or disabling sync rebuilds the app's data session around
the same local store, so the change takes effect immediately without a manual
relaunch. During that handoff Nagare releases the outgoing history monitor,
CloudKit event monitor, and model container before opening
the replacement. A failed handoff reopens the prior configuration and leaves
the saved preference unchanged. Disabling sync preserves the local database
and stops future replication on that device, but does not claim to delete the
user's existing private CloudKit copy.

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
side of a relationship. Persistent-history events publish a fresh immutable
snapshot immediately. A successful CloudKit import event separately asks
`SyncIntegrityMonitor` to debounce `SyncIntegrityRepair`, so ordinary local
edits do not trigger a complete reconciliation scan. Repair also runs at
launch and after later foreground activations.

SwiftUI reads one immutable `NagareDataSnapshot`. A history event uses a fresh
read context to reconstruct and publish the complete value graph. Import-driven
semantic reconciliation follows through another fresh short-lived context and
publishes again only when the repair actually changed persisted data.
SwiftData records never cross the repository boundary. This is intentional:
independently coordinated updates can leave objects registered in a long-lived
context stale even while inserts appear. An integration test opens the same
store through two coordinators, materializes a snapshot in the reader, changes
the record in the writer, and requires history-driven publication of the new
value.

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

The immutable app snapshot uses the identical canonical ordering for its ID
indexes. This prevents a transient duplicate from crashing or making a command
depend on fetch order while the persistent-history repair is still debouncing.

## CloudKit environments

The shared container is `iCloud.ilia.page.nagare`. Development-signed builds
use CloudKit's development environment; distribution builds use production.
The two databases are isolated even though the container identifier is the
same. Debug and release builds also use separate bundle identifiers and app
groups.

Debug also uses a dedicated `NagareDev.store` and a Debug-only sync preference.
Release keeps SwiftData's existing production store and preference. A fresh
Nagare Dev build therefore opens deterministic sample data without attaching
to CloudKit unless development sync is explicitly enabled.

The app remains usable offline or while account status cannot be determined.
Settings keeps sync as a simple on/off preference; transport details remain
internal because there is no user action that can reliably accelerate or
repair CloudKit transport.
Framework import/export failures are retried by the persistent CloudKit stack;
history observation, partial imports, and semantic repair failures are nonfatal
and retry indefinitely with a capped delay. Foreground activation resets those
retries immediately.

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

The targeted physical regression matrix now passes on an iPhone 17 Pro and an
Apple-silicon Mac: title edits and Today reorders propagated in both directions
while both apps remained open, with no relaunch or manual refresh. Phone-to-Mac
delivery was observably slower than Mac-to-phone delivery, but every tested
change reached the already-rendered immutable snapshot. This asymmetry is
acceptable eventual-consistency behavior, not the former stale-context defect.

The broader release matrix below remains mandatory before promoting the
development schema. Automated partial-import coverage and this targeted matrix
remove the known `VIRTUAL-001` and stale-publication defects; they do not yet
cover every command, recurrence transition, or offline conflict on real
devices.

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
2. Enable iCloud in Nagare Settings on both test devices and verify that each
   active session reconnects without a relaunch. Sign into the same test
   iCloud account on an iPhone and a Mac. Exercise
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
