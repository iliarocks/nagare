# Nagare code and behavior audit

Reviewed October 1, 2026 alongside the UI/UX changes on
`codex/binary-project-priority`. This report covers editor state, recurrence,
ordering, persistence, sync reconciliation, and the tests around those paths.
MCP design is outside this audit.

The findings below follow concrete source paths. Unless explicitly noted, they
have not been reproduced interactively or under live cross-device sync. They are
follow-up work; the UI/UX branch does not implement these broader fixes.

## Fix editor state first

### 1. Reverting a schedule in the same editor can leave the previous edit saved

`Features/Items/TodoScheduleEditor.swift`, `save()` compares the form with the
immutable item supplied when the editor opened. Changing A → B saves B, but
changing back to A returns early because the form now equals that opening item.
Adding then removing a time has the same problem. The form can therefore show
values different from the database.

Compare against a successfully saved baseline or the latest stored schedule.
Regression: add time, remove time without dismissing, reopen and verify that the
item is untimed. Also cover date A → B → A and failed saves.

### 2. Dismissing an untouched repeat editor can overwrite a synced edit

`Features/Recurrence/RecurrenceEditor.swift` saves unconditionally on disappearance
and submits its opening form and template time values. A rule/time update arriving
from another device while the editor is open can be overwritten on dismissal,
even if the local user changed nothing.

Track dirty fields, skip unchanged saves, and obtain values for untouched fields
from the latest record. Test an external template update during an open, untouched
editor, then dismiss. Test local rule edits alongside external time edits too.

### 3. Editing notes can overwrite a newly synced title, and vice versa

`Features/Notes/NotesView.swift` and
`Features/Projects/ProjectDetailView.swift` duplicate an all-or-nothing draft
policy: when either text field is dirty, `load` ignores the entire refreshed
record; `save` later submits both local fields. An unrelated remote edit to the
other field is consequently overwritten.

Keep a baseline and dirty state per field. Refresh unchanged fields and merge
only locally edited fields into the latest record before writing. Same-field
conflicts still need an explicit policy. Regression: edit local notes, deliver
a remote title update, autosave, and verify both changes survive.

### 4. A blank project title silently prevents notes from saving

`Features/Projects/ProjectDetailView.swift`, `saveProject()` returns when the title
is blank, including its dismissal save. Clearing the title and editing notes can
lose the notes draft without feedback.

Either retain the last valid title while saving notes, or surface validation and
retain the unsaved draft. Choose the desired behavior before implementing it.

These four findings point to one useful simplification: a small shared draft
state abstraction for saved baselines, dirty fields, debouncing, and flushing.
Keep native view controls and persistence transactions in their existing layers.
Also verify immediate iOS backgrounding during a debounce: the current
`Features/Shared/AppTermination.swift` callback is macOS-only, and iOS background
flushing is not explicit. Data loss here is a hypothesis requiring lifecycle
testing, not a reproduced finding.

## Tighten domain rules

### 5. Reassigning a completed recurring item can move its future series

`Domain/Logic/NagareCommandPlanner.swift`, `assign(.item, ...)` forwards the item's
recurrence-template ID even when the item is completed.
`Infrastructure/Persistence/SwiftDataNagareRepository.swift`, `assign` then
updates that template's project as well as the historical item.

Source-derived reproduction steps: complete a recurring item in project A; open its completed
notes and assign project B. The historical item and template move to B while the
current active occurrence stays in A. Completing that active occurrence creates
the next one in B. Reconciliation does not repair this membership mismatch.

Make historical-item assignment and active-series assignment explicit. Test
completed-item assignment through the application command boundary and assert
the active item and future series retain the intended project.

### 6. End times earlier than start times are accepted

`Features/Items/TodoScheduleEditor.swift` combines both times with the selected
date. The repository accepts the supplied end date, and recurrence transition
validation checks same-day membership rather than chronological order. Setting
16:00–15:00 is therefore accepted. Opening the editor for an existing 23:30 item
without an end time and adding an end defaults to 00:30 on the same date.

Decide whether overnight intervals are supported. Centralize that policy in
schedule validation and use it for creation, edits, imports, and recurrence.
Test reverse ranges, equal endpoints, midnight crossings, and daylight-saving
transitions.

### 7. An idle foreground app has no midnight invalidation

`Features/Today/TodayView.swift` reads the current date without observing a clock.
`Features/Upcoming/UpcomingView.swift` caches projections and refreshes for data,
navigation, and scene activation; `App/RootView.swift` runs maintenance on
appearance and activation. There is no explicit day-boundary trigger while the
app remains continuously active.

Use one shared observable calendar day, updated at midnight and on activation or
time-zone changes, to drive both maintenance and projections. Verify with an
injected clock; a live midnight reproduction has not been performed.

## Remove competing implementations and avoid repeated work

### 8. Some persistence tests exercise unused parallel writers

The standalone reinstatement path in
`Infrastructure/Persistence/Workflows/RecurrencePersistence.swift` and assignment
paths in `Workflows/ProjectMembership.swift` have test callers but no production
callers for those operations. Production uses `NagareCommandPlanner` and the
repository. Their ordering policies already differ: the active planner repairs
missing project order values, while the legacy allocation path rejects them.

Move valuable regression cases to `NagareDataOrchestrator`/repository commands,
then delete unused write entry points and helpers. Preserve legacy persisted
model shapes required to open existing stores.

### 9. Reconciliation rescans a series' history once per occurrence sequence

`Domain/Logic/SyncReconciliationPlanner.swift` filters all occurrences for every
sequence, with additional later-sequence scans while repairing history. This is
quadratic work for a long-running series and runs from a main-actor monitor.

Group by template and sequence once, keeping deterministic winner selection.
Benchmark several years of daily history and assert the same reconciliation
plan before and after. Responsiveness impact has not been measured yet.

### 10. Selection and navigation state have small cleanup opportunities

`ReorderableItemList` and `ProjectDetailView` duplicate selection toggling,
context-item resolution, and pruning. These are candidates for shared pure
operations. The removed repeat-to-Upcoming action also leaves scroll-target
plumbing that currently has no user-facing caller; remove or retain it only for
a concrete navigation requirement.

## Priority compatibility verified by this change

The active priority model has normal and high states. Legacy raw zero decodes as
normal; stored fields remain intact. On loading a legacy batch, low projects
append after existing normal projects, preserving order within the batch and
existing valid normal keys. Later arriving low records append without moving
already-normal projects. If low records arrive first, later normal records keep
their stored keys and can appear after those migrated low records. In either
arrival order, original tier order across separate historical sync batches is
not reconstructed; existing migrated keys remain stable. Duplicate semantic IDs
defer migration until reconciliation.

Coverage includes old-archive import, canonical export, persistent-store upgrade,
record timestamps, child order/membership, and late-arrival stability. Live
cross-device CloudKit delivery and production-schema behavior remain unverified.

## Suggested sequence

1. Fix schedule baselines and shared draft/autosave behavior, with focused
   regressions for local edits, sync refreshes, failed saves, and backgrounding.
2. Set explicit historical recurrence membership and interval-validation rules.
3. Add shared day-boundary invalidation.
4. Move tests onto production write paths, remove redundant writers, and
   benchmark/rework reconciliation scans.

Success means fewer owners of each behavior and fewer ways for the UI and stored
state to disagree. No broad architecture replacement is needed.
