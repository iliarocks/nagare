# Upgrade fixture

`PreCleanupV5.store` is a frozen SQLite store generated using Nagare commit
`ec6fba5`, before the environment cleanup, with Xcode 27 RC (27A266a).
It uses schema version 5 and contains only synthetic data: a project, timed task,
completed task, recurring task/template, and a legacy event.

The upgrade test copies this file before opening it with the current model. It
checks relationships, dates, notes and recurrence, then edits and reopens the
copy. Do not regenerate the fixture from current models as part of the test.
This covers this pre-cleanup schema, not every historical schema or CloudKit.
