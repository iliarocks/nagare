#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failure_count=0

report_failure() {
    printf '%s:%s: error: %s\n' "$1" "$2" "$3" >&2
    failure_count=$((failure_count + 1))
}

lint_imports() {
    local relative_directory="$1"
    shift
    local directory="${repository_root}/${relative_directory}"
    local allowed_modules=" $* "
    local source_files

    [[ -d "${directory}" ]] || return

    if ! source_files="$(find "${directory}" -type f -name '*.swift' -print)"; then
        report_failure \
            "${directory}" \
            0 \
            "Architecture lint could not scan this directory"
        return
    fi

    while IFS= read -r source_file; do
        [[ -n "${source_file}" ]] || continue
        local import_lines
        local grep_status=0
        import_lines="$(
            grep -nE '^[[:space:]]*import[[:space:]]+' "${source_file}"
        )" || grep_status=$?
        if (( grep_status > 1 )); then
            report_failure \
                "${source_file}" \
                0 \
                "Architecture lint could not read this source file"
            continue
        fi

        while IFS=: read -r line_number import_line; do
            [[ -n "${line_number}" ]] || continue
            local module
            module="$(sed -E 's/^[[:space:]]*import[[:space:]]+([A-Za-z0-9_]+).*$/\1/' <<< "${import_line}")"
            if [[ "${allowed_modules}" != *" ${module} "* ]]; then
                report_failure \
                    "${source_file}" \
                    "${line_number}" \
                    "${relative_directory} may not import ${module}; allowed imports: $*"
            fi
        done <<< "${import_lines}"
    done <<< "${source_files}"
}

lint_forbidden_symbols() {
    local relative_directory="$1"
    local forbidden_pattern="$2"
    local explanation="$3"
    local directory="${repository_root}/${relative_directory}"
    local matches
    local grep_status=0

    [[ -d "${directory}" ]] || return

    matches="$(
        grep -RInE \
            --include='*.swift' \
            "${forbidden_pattern}" \
            "${directory}"
    )" || grep_status=$?
    if (( grep_status > 1 )); then
        report_failure \
            "${directory}" \
            0 \
            "Architecture lint could not scan this directory"
        return
    fi

    while IFS=: read -r source_file line_number _; do
        [[ -n "${source_file}" ]] || continue
        report_failure "${source_file}" "${line_number}" "${explanation}"
    done <<< "${matches}"
}

# Inner layers only know the standard library/Foundation. Framework-specific
# APIs must stay behind a port and an Infrastructure adapter.
lint_imports "Nagare/Domain" Foundation
lint_imports "Nagare/Application" Foundation
lint_imports "Nagare/Infrastructure/Persistence" Foundation SwiftData
lint_imports "Shared/Domain" Foundation
lint_imports "Shared/Infrastructure" Foundation

lint_forbidden_symbols \
    "Nagare/Domain" \
    'ModelContext|@Model|UserDefaults|FileManager|WidgetCenter|CSSearchableIndex|autoupdatingCurrent|Date\.now|\.now\b' \
    "Domain code may only use immutable values and explicit deterministic inputs"

# Domain structs are values, not mutable bags shared between planners. Local
# variables inside pure functions may mutate; stored properties may not.
domain_stored_var_matches=""
domain_stored_var_status=0
domain_stored_var_matches="$(
    grep -RInE \
        --include='*.swift' \
        '^[[:space:]]{4}(private[[:space:]]+)?var[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(:|=).*(\{|get[[:space:]]*\{)?[[:space:]]*$' \
        "${repository_root}/Nagare/Domain/Models"
)" || domain_stored_var_status=$?
if (( domain_stored_var_status > 1 )); then
    report_failure \
        "${repository_root}/Nagare/Domain/Models" \
        0 \
        "Architecture lint could not scan immutable Domain models"
fi
while IFS=: read -r source_file line_number _; do
    [[ -n "${source_file}" ]] || continue
    source_line="$(sed -n "${line_number}p" "${source_file}")"
    if [[ "${source_line}" == *"{"* ]]; then
        continue
    fi
    report_failure \
        "${source_file}" \
        "${line_number}" \
        "Domain model stored properties must be immutable let values"
done <<< "${domain_stored_var_matches}"

lint_forbidden_symbols \
    "Nagare/Application" \
    'ModelContext|@Model|UserDefaults|FileManager|WidgetCenter|CSSearchableIndex' \
    "Application orchestrators must perform I/O through ports"

# Save/rollback and sync-metadata semantics belong to one transaction adapter.
# A second save path can silently bypass modification stamps or rollback.
direct_save_matches=""
direct_save_grep_status=0
direct_save_matches="$(
    grep -RInE \
        --include='*.swift' \
        --exclude='SwiftDataTransaction.swift' \
        '(modelContext|context)\.save\(' \
        "${repository_root}/Nagare"
)" || direct_save_grep_status=$?
if (( direct_save_grep_status > 1 )); then
    report_failure \
        "${repository_root}/Nagare" \
        0 \
        "Architecture lint could not scan for direct persistence calls"
fi

while IFS=: read -r source_file line_number _; do
    [[ -n "${source_file}" ]] || continue
    report_failure \
        "${source_file}" \
        "${line_number}" \
        "Direct ModelContext saves must use SwiftDataTransaction"
done <<< "${direct_save_matches}"

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
