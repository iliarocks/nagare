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
