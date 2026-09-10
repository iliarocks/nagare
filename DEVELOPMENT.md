# Development

Use **Xcode 27 RC, build 27A266a**. Select it in Xcode's Locations settings or
with `sudo xcode-select --switch /Applications/Xcode.app`. Run Xcode's first-launch
setup and install the iOS 27 simulator runtime. The scripts report a toolchain
mismatch; set `EXPECTED_XCODE_BUILD` only when intentionally checking another
reviewed Xcode version.

## Builds and tests

Run commands from this repository:

```sh
Scripts/check.sh macos unit
Scripts/check.sh ios all
TEST_DESTINATION='generic/platform=iOS' Scripts/check.sh ios build
Scripts/check.sh macos build
Scripts/check.sh macos ui
```

The second argument accepts `unit`, `ui`, `all`, or `build`. iOS tests default to
an iPhone 17 simulator. Set `TEST_DESTINATION` to a complete Xcode destination
(e.g. `platform=iOS Simulator,id=...`) when selecting a particular device/runtime.
Run UI tests with the desktop available for automation. Stop a run if an Apple
simulator service repeatedly crashes; do not hide global crash reports.

Build output lives in `.build/derived/<platform>`, and the latest result for each
suite lives in `.build/results`. Both are disposable and ignored by Git.

## Development data

Debug builds use `ilia.page.nagare.dev` and a separate `NagareDev.store`.
The Mac app is named **Nagare Dev**. Release builds use `ilia.page.nagare`.
Development builds on iPhone and Mac use the same CloudKit development container;
they do not sync with the production App Store database. Enable iCloud sync in
both apps and restart them after changing that setting.

Hosted unit tests use in-memory stores. UI tests use a dedicated regression store.
Upgrade tests copy a frozen synthetic fixture before opening it; never use a
personal database as a committed fixture. `NagareTests/Fixtures/README.md` records
its provenance.

## Local release archives

Commit the reviewed source, then run:

```sh
Scripts/archive.sh ios
Scripts/archive.sh macos
```

Archives live in `.build/releases/<version>-<build>-<platform>/Nagare.xcarchive`.
Each has a `source.txt` recording its commit and Xcode build. The script refuses
a dirty checkout or an existing archive path. `Scripts/ExportOptions.plist` holds
the App Store export settings. Archiving does not upload, submit or publish.

Keep each submitted archive and its dSYMs while it is needed for debugging.
Unlike source, these ignored files cannot be recovered from Git. Remove obsolete
DerivedData, test output and superseded local experiments instead of keeping
ad-hoc backup directories.

## Before publishing

- Run unit/UI checks on iPhone and Mac using the RC environment.
- Open an existing store and verify notes, dates, completed tasks, projects and recurrence.
- Test development iPhone/Mac sync: create/edit/complete, go offline, reconnect, and restart.
- Separately verify the production CloudKit schema and cross-device behavior with the distribution build. Development signing cannot establish production readiness.
- Validate the signed archive, privacy manifest and entitlements; upload only after approval, then confirm processing and the selected App Store build.

The public website lives in `docs`; maintained repository documentation belongs
outside that folder. Raw screenshots and final designs remain separate under
`screenshots`, as described in its README.
