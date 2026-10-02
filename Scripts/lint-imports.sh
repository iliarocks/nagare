#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failure_count=0

report_failure() {
    printf '%s:%s: error: %s\n' "$1" "$2" "$3" >&2
    failure_count=$((failure_count + 1))
}

scan() {
    local callback="$1" detail="$2" relative_directory="$3" pattern="$4"
    shift 4
    local directory="${repository_root}/${relative_directory}" matches grep_status=0
    matches="$(grep -RInE --include='*.swift' "$@" -- "$pattern" "$directory")" || grep_status=$?
    if (( grep_status > 1 )); then
        report_failure "$directory" 0 "Architecture lint could not scan this directory"
        return
    fi
    while IFS=: read -r source_file line_number source_line; do
        [[ -n "$source_file" ]] || continue
        "$callback" "$relative_directory" "$detail" "$source_file" "$line_number" "$source_line"
    done <<< "${matches}"
}

check_import() {
    local relative_directory="$1" allowed_modules="$2" source_file="$3" line_number="$4" source_line="$5"
    [[ "$source_line" =~ ^[[:space:]]*import[[:space:]]+([A-Za-z0-9_]+) ]]
    local module="${BASH_REMATCH[1]}"
    if [[ " $allowed_modules " != *" $module "* ]]; then
        report_failure "$source_file" "$line_number" "$relative_directory may not import $module; allowed imports: $allowed_modules"
    fi
}

report_forbidden() { report_failure "$3" "$4" "$2"; }
lint_imports() {
    local directory="$1"; shift
    scan check_import "$*" "$directory" '^[[:space:]]*import[[:space:]]+'
}
lint_forbidden_symbols() {
    local directory="$1" pattern="$2" explanation="$3"; shift 3
    scan report_forbidden "$explanation" "$directory" "$pattern" "$@"
}

# Inner layers only know the standard library/Foundation. Framework-specific
# APIs must stay behind a port and an Infrastructure adapter.
lint_imports "Nagare/Domain" Foundation
lint_imports "Nagare/Application" Foundation
lint_imports "Nagare/Infrastructure/Persistence" Foundation SwiftData

lint_forbidden_symbols \
    "Nagare/Domain" \
    'ModelContext|@Model|UserDefaults|FileManager|autoupdatingCurrent|Date\.now|\.now\b' \
    "Domain code may only use immutable values and explicit deterministic inputs"

# Domain structs are values, not mutable bags shared between planners. Local
# variables inside pure functions may mutate; stored properties may not.
lint_forbidden_symbols \
    "Nagare/Domain/Models" \
    '^[[:space:]]{4}(private[[:space:]]+)?var[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(:|=)[^{]*$' \
    "Domain model stored properties must be immutable let values"

lint_forbidden_symbols \
    "Nagare/Application" \
    'ModelContext|@Model|UserDefaults|FileManager|URLSession|NotificationCenter\.default|ProcessInfo|Bundle\.main|autoupdatingCurrent|Date\.now|\.now\b' \
    "Application orchestrators must perform I/O through ports"

# Features render immutable snapshots and send ID-addressed commands. They may
# not import, observe, save, or retain persistence-framework objects.
lint_forbidden_symbols \
    "Nagare/Features" \
    'import[[:space:]]+SwiftData|@Query|@Model|ModelContext|SwiftDataTransaction|SwiftDataLiveResults|ResultsObserver' \
    "Features may only consume immutable snapshots and application commands"
lint_forbidden_symbols \
    "Nagare/Features" \
    '(^|[^A-Za-z0-9_])RecurrencePersistence([^A-Za-z0-9_]|$)' \
    "Persistence workflows belong behind application ports"
lint_forbidden_symbols \
    "Nagare/Features" \
    '(:|->|as[?!]?|<|\[)[[:space:]]*(Todo|Event|Project|RecurrenceTemplate)([?>,\])[:space:]]|$)' \
    "Features may not retain mutable SwiftData record types"
lint_forbidden_symbols \
    "Nagare/App" \
    '@Query|SwiftDataLiveResults|ResultsObserver|dataStore\?\.' \
    "App views must publish the immutable NagareDataSnapshot"
lint_forbidden_symbols \
    "Nagare/Features" \
    'dataStore\?\.' \
    "Feature commands must not silently disappear when composition is invalid"
# Only the composition root, schema bootstrap, and history bridge may know
# SwiftData in App. SwiftUI delivery views and observable stores are values-only.
lint_forbidden_symbols \
    "Nagare/App" \
    'import[[:space:]]+SwiftData' \
    "Only App composition and history bridge files may import SwiftData" \
    --exclude=NagareApp.swift --exclude=NagareCloudSchemaInitializer.swift --exclude=SyncIntegrityMonitor.swift

# Save/rollback and sync-metadata semantics belong to one transaction adapter.
# A second save path can silently bypass modification stamps or rollback.
lint_forbidden_symbols \
    "Nagare" \
    '(modelContext|context)\.save\(' \
    "Direct ModelContext saves must use SwiftDataTransaction" \
    --exclude=SwiftDataTransaction.swift

# SwiftData and CloudKit policy belongs in Domain planners, never in an
# Infrastructure adapter or mutable record type.
lint_forbidden_symbols \
    "Nagare/Infrastructure/Persistence" \
    'canonicalRecord|canonicalOccurrence|groupsWithDuplicateIDs|isLowerPriority|SyncReconciliationPlanner\.plan|RecurrenceProjectionLogic\.generate' \
    "Persistence adapters may translate and apply plans but may not decide conflict policy"

if (( failure_count > 0 )); then
    printf 'Import boundary lint failed with %d violation(s).\n' "${failure_count}" >&2
    exit 1
fi

printf 'Import boundary lint passed.\n'
