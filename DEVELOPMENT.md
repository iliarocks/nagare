# Development

Use Xcode 27, build **27A266a**. The check script enforces this version; override
`EXPECTED_XCODE_BUILD` only when deliberately evaluating another toolchain.

## Build and test

```sh
Scripts/check.sh macos all
Scripts/check.sh ios all
TEST_DESTINATION='platform=iOS,id=<device-UDID>' Scripts/check.sh ios build
Scripts/check.sh macos build
```

The second argument accepts `unit`, `ui`, `all`, or `build`. iOS defaults to the
iPhone 17 simulator. Output goes to ignored `.build/derived` and `.build/results`.
Quit the installed Mac development copy before UI tests to avoid two running
apps with the same bundle ID. Tests use isolated stores; the frozen upgrade
fixture and its provenance live in `NagareTests/Fixtures`.

## Code boundaries

- Domain contains immutable values and deterministic rules; Application issues
  commands through persistence ports. Both depend only on Foundation.
- Infrastructure owns SwiftData records and transactions. App publishes immutable
  snapshots; Features render them and send commands, without retaining records.
- All saves use `SwiftDataTransaction`. Put each rule on its production command
  path and test that path; avoid parallel compatibility writers.
- Preserve legacy persisted models/fields needed to open existing stores. Schema
  version 5 relies on automatic migration, verified with the frozen fixture.
- Root owns maintenance and the calendar day. Shared editor drafts own saved
  baselines; autosave flushes on dismissal, backgrounding, and Mac termination.
  Text writes contain only edited fields; local edits win same-field conflicts.

`Scripts/lint-imports.sh` enforces these boundaries. Keep native platform controls,
shared presentation primitives, neutral selection, and autosave. Closing the main
Mac window intentionally quits the app. Project priority highlights active items
in Today/Upcoming without changing their order.

## Development data

Debug builds use `ilia.page.nagare.dev`, `NagareDev.store`, and the CloudKit
**development** environment. Release builds use `ilia.page.nagare` and production.
iCloud preference changes apply on the next launch.

To install matching fixtures, back up both development stores, their WAL/SHM
files, and preferences. Seed **one device**, then let iCloud deliver to the other:

```text
--enable-development-cloud-sync
--replace-with-development-sample-data
--development-sample-reference=2026-10-01T21:00:00Z
--development-sample-time-zone=America/Los_Angeles
```

Launch the receiver with only `--enable-development-cloud-sync`; ordinary later
launches retain data and sync. On Mac, use the normal app launcher, such as
`open -a "Nagare Development" --args ...`, so system background-task registration works.
The fixture contains 3 projects, 15 items, and 3 recurring series. Stable logical
IDs do not make separately seeded CloudKit records identical.

## Cloud MCP

`mcp/` contains the development Cloudflare Worker. With Node 26, run `npm ci`,
`npm run check`, and `npm test` there. Tests use isolated storage and fake Apple
responses; they never touch an iCloud account. `npm run deploy` publishes the
development endpoint at `https://mcp.development.nagare.page`.

The production endpoint will be `https://mcp.nagare.page`, with its own Worker,
OAuth storage, and production CloudKit API token. Both environments serve MCP at the root URL.

The Worker uses one OAuth KV namespace and a Durable Object per connected user
for credentials, calendar interpretation, and serialized CloudKit calls. Idle credentials expire
after 30 days. Tasks remain in CloudKit. `CLOUDKIT_API_TOKEN` is a Worker secret;
local development uses ignored `.dev.vars`. The CloudKit token uses Post Message
sign-in and allows only the Worker origin. Keep it in development while testing.

Tools manage tasks, projects, ordering, priority, and recurring series. Ordinary
queries include active tasks and projected repeats; completed history is separate.
Today carries overdue items forward even when the apps are closed. Reads use a
fresh CloudKit zone snapshot; commands require current revisions and commit atomically
(up to CloudKit’s 200-operation limit). Large day rollovers run in ordered batches
before the requested command. Create retries reuse a UUID. Verify changes
through both development apps, including recurrence and large-note round trips.

## Release and assets

Run unit/UI checks on both platforms, verify existing-store upgrades and
cross-device create/edit/complete/restart behavior, then commit. Archive with
`Scripts/archive.sh ios` or `Scripts/archive.sh macos`. Archives and source commit
metadata live in `.build/releases`; keep submitted archives and dSYMs. Archiving
does not upload or publish. Validate the distribution build's production CloudKit
schema and sync separately before submission.

`docs/` is the public website; `docs/CNAME` binds GitHub Pages to `nagare.page`.
`screenshots/` holds original captures and App Store exports. Rebuild the exports
with `swift screenshots/render.swift`; the Apple bezel and its license are adjacent.
