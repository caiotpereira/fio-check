#!/usr/bin/env sh
# =============================================================================
# test_fio_check.sh — Exercises all commands and options of fio-check.sh
#
# Usage:
#   cd /path/to/fio-check
#   ./test_fio_check.sh       # normal run
#   ./test_fio_check.sh -v    # verbose: show captured output on failure
#
# Exit: 0 = all tests passed, 1 = one or more failed
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIO="${SCRIPT_DIR}/fio-check.sh"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

# =============================================================================
#  Test counters and shared state
# =============================================================================
PASS=0
FAIL=0
SKIP=0

OUTPUT=""        # stdout+stderr captured from the last run() call
EXIT_CODE=0      # exit code from the last run() call
CURRENT_TEST=""  # name set by check() for the next assertion

# =============================================================================
#  Temp workspace  (auto-cleaned on exit or interrupt)
# =============================================================================
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "${WORK_DIR}"' EXIT INT TERM

# =============================================================================
#  Framework helpers
# =============================================================================

# section <title>
#   Print a bold section header to group related tests visually.
section() {
    printf '\n\033[1m── %s ──\033[0m\n' "$*"
}

# check <description>
#   Name the next assertion.  Call before each expect_* or expect_no_ansi.
check() {
    CURRENT_TEST="$1"
}

# run [args...]
#   Run fio-check.sh with the given arguments.
#   Captures combined stdout+stderr into OUTPUT and saves the exit code.
run() {
    set +e
    OUTPUT=$("${FIO}" "$@" 2>&1)
    EXIT_CODE=$?
    set -e
}

# pass / fail <reason>
#   Record a test result.  Called internally by the expect_* helpers.
pass() {
    PASS=$((PASS + 1))
    printf '  \033[32m✓\033[0m %s\n' "${CURRENT_TEST}"
}

fail() {
    FAIL=$((FAIL + 1))
    printf '  \033[31m✗\033[0m %s\n    └─ %s\n' "${CURRENT_TEST}" "$1"
    if [ "${VERBOSE}" -eq 1 ]; then
        printf '%s\n' "${OUTPUT}" | head -15 | sed 's/^/      /'
    fi
}

skip() {
    SKIP=$((SKIP + 1))
    printf '  \033[33m~\033[0m %s  [%s]\n' "${CURRENT_TEST}" "$1"
}

# =============================================================================
#  Assertion helpers
# =============================================================================

# expect_exit <code>
#   Assert the last run() exited with exactly <code>.
expect_exit() {
    if [ "${EXIT_CODE}" -eq "$1" ]; then
        pass
    else
        fail "expected exit $1, got ${EXIT_CODE}"
    fi
}

# expect_exit_any <code> [code ...]
#   Assert the last run() exited with one of the given codes.
#   Used for tests whose result depends on what is installed on the host.
expect_exit_any() {
    local matched=0
    for code in "$@"; do
        [ "${EXIT_CODE}" -eq "${code}" ] && matched=1 && break
    done
    if [ "${matched}" -eq 1 ]; then
        pass
    else
        fail "expected exit code in ($*), got ${EXIT_CODE}"
    fi
}

# expect_output_has <pattern>
#   Assert the captured output matches <pattern> (basic regex via grep).
expect_output_has() {
    if printf '%s\n' "${OUTPUT}" | grep -q "$1"; then
        pass
    else
        fail "output does not contain: $1"
    fi
}

# expect_output_not_has <pattern>
#   Assert the captured output does NOT match <pattern>.
expect_output_not_has() {
    if printf '%s\n' "${OUTPUT}" | grep -q "$1"; then
        fail "output should not contain: $1"
    else
        pass
    fi
}

# expect_file_exists <path>
#   Assert that a file exists at <path>.
expect_file_exists() {
    if [ -f "$1" ]; then
        pass
    else
        fail "file not found: $1"
    fi
}

# expect_file_has <path> <pattern>
#   Assert that a file exists and its content matches <pattern>.
expect_file_has() {
    if [ -f "$1" ] && grep -q "$2" "$1"; then
        pass
    else
        fail "file '$1' does not contain: $2"
    fi
}

# expect_no_ansi
#   Assert the captured output contains no ANSI escape sequences.
#   cat -v makes the ESC byte visible as ^[ so grep -F can find it reliably.
expect_no_ansi() {
    if printf '%s\n' "${OUTPUT}" | cat -v | grep -qF '^['; then
        fail "ANSI escape sequences found in output"
    else
        pass
    fi
}

# =============================================================================
#  SECTION 1 — Preconditions
# =============================================================================
section "Preconditions"

check "fio-check.sh exists"
[ -f "${FIO}" ] && pass || fail "not found: ${FIO}"

check "fio-check.sh is executable"
[ -x "${FIO}" ] && pass || fail "not executable: ${FIO}"

# =============================================================================
#  SECTION 2 — Help / Usage
# =============================================================================
section "Help / Usage"

check "help command exits 0"
run help
expect_exit 0

check "help command shows USAGE section"
expect_output_has "USAGE"

check "help command shows COMMANDS section"
expect_output_has "COMMANDS"

check "help command shows OPTIONS section"
expect_output_has "OPTIONS"

check "--help flag exits 0"
run --help
expect_exit 0

check "--help flag shows tool name"
expect_output_has "fio-check"

check "-h short flag exits 0"
run -h
expect_exit 0

check "no arguments shows usage and exits 0"
run
expect_exit 0

check "no arguments output contains USAGE"
expect_output_has "USAGE"

check "unknown command exits 1"
run bad-command
expect_exit 1

check "unknown command shows error message"
expect_output_has "Unknown"

check "unknown option exits 1"
run --bad-flag
expect_exit 1

# =============================================================================
#  SECTION 3 — list-libs
# =============================================================================
section "list-libs"

check "list-libs exits 0"
run list-libs
expect_exit 0

check "list-libs output shows lib_docker"
expect_output_has "lib_docker"

check "list-libs output shows foundries group"
expect_output_has "foundries"

# --verbose: list-libs does not call check_* functions so no VERB lines
# are expected, but the flag must not cause a crash
check "list-libs --verbose exits 0"
run --verbose list-libs
expect_exit 0

check "list-libs --quiet exits 0"
run --quiet list-libs
expect_exit 0

check "list-libs --no-color exits 0"
run --no-color list-libs
expect_exit 0

check "list-libs --no-color produces no ANSI escape sequences"
expect_no_ansi

check "list-libs --lib-dir <valid path> exits 0"
run --lib-dir "${SCRIPT_DIR}/lib" list-libs
expect_exit 0

check "list-libs --lib-dir <valid path> shows lib_docker"
expect_output_has "lib_docker"

check "list-libs --lib-dir <empty dir> exits 0 with warning"
run --lib-dir "${WORK_DIR}" list-libs
expect_exit 0

check "list-libs --lib-dir <empty dir> output mentions no modules found"
expect_output_has "No lib modules\|not found"

check "list-libs --lib-dir <nonexistent path> exits 0"
run --lib-dir "/no_such_dir_xyz" list-libs
expect_exit 0

# =============================================================================
#  SECTION 4 — list-profiles
# =============================================================================
section "list-profiles"

check "list-profiles exits 0"
run list-profiles
expect_exit 0

check "list-profiles output shows at least one profile"
expect_output_has "docker\|foundries"

check "list-profiles --profiles-dir <valid path> exits 0"
run --profiles-dir "${SCRIPT_DIR}/profiles" list-profiles
expect_exit 0

check "list-profiles --profiles-dir <valid path> shows docker profile"
expect_output_has "docker"

check "list-profiles --profiles-dir <empty dir> exits 0 with warning"
run --profiles-dir "${WORK_DIR}" list-profiles
expect_exit 0

check "list-profiles --profiles-dir <empty dir> output mentions no profiles found"
expect_output_has "No profiles\|not found"

check "list-profiles --no-color exits 0"
run --no-color list-profiles
expect_exit 0

check "list-profiles --no-color produces no ANSI escape sequences"
expect_no_ansi

# =============================================================================
#  SECTION 5 — check-cmd
# =============================================================================
section "check-cmd"

# Basic pass / fail
check "check-cmd sh exits 0 (sh is always present)"
run check-cmd sh
expect_exit 0

check "check-cmd sh output shows OK"
expect_output_has "OK"

check "check-cmd sh ls cat exits 0 (all present)"
run check-cmd sh ls cat
expect_exit 0

check "check-cmd <nonexistent> exits 1"
run check-cmd __nonexistent_xyz_404__
expect_exit 1

check "check-cmd <nonexistent> output shows FAIL or missing"
expect_output_has "FAIL\|missing"

check "check-cmd sh <nonexistent> exits 1 when any command is missing"
run check-cmd sh __nonexistent_xyz_404__
expect_exit 1

# --dry-run
check "--dry-run check-cmd exits 0"
run --dry-run check-cmd sh
expect_exit 0

check "--dry-run check-cmd output shows DRY marker"
expect_output_has "DRY"

check "--dry-run check-cmd does not log an OK result"
expect_output_not_has "\[ OK \]"

# --verbose
check "--verbose check-cmd exits 0"
run --verbose check-cmd sh
expect_exit 0

check "--verbose check-cmd output shows VERB lines"
expect_output_has "VERB"

# --quiet
check "--quiet check-cmd exits 0"
run --quiet check-cmd sh
expect_exit 0

check "--quiet check-cmd suppresses OK output"
expect_output_not_has "\[ OK \]"

# --no-color
check "--no-color check-cmd exits 0"
run --no-color check-cmd sh
expect_exit 0

check "--no-color check-cmd produces no ANSI escape sequences"
expect_no_ansi

check "--no-color check-cmd still shows OK as plain text"
expect_output_has "OK"

# --filter
check "--filter ok check-cmd sh exits 0"
run --filter ok check-cmd sh
expect_exit 0

check "--filter ok check-cmd sh shows OK result"
expect_output_has "OK"

check "--filter fail check-cmd sh exits 0"
run --filter fail check-cmd sh
expect_exit 0

check "--filter fail check-cmd sh hides OK result"
expect_output_not_has "\[ OK \]"

check "--filter fail check-cmd <nonexistent> exits 1"
run --filter fail check-cmd __nonexistent_xyz_404__
expect_exit 1

check "--filter fail check-cmd <nonexistent> shows FAIL"
expect_output_has "FAIL\|missing"

check "--filter warn check-cmd sh exits 0"
run --filter warn check-cmd sh
expect_exit 0

# =============================================================================
#  SECTION 6 — check-kconfig
# =============================================================================
section "check-kconfig"

check "--dry-run check-kconfig CONFIG_NET exits 0"
run --dry-run check-kconfig CONFIG_NET
expect_exit 0

check "--dry-run check-kconfig CONFIG_NET output shows DRY"
expect_output_has "DRY"

check "--dry-run check-kconfig CONFIG_INET exits 0"
run --dry-run check-kconfig CONFIG_INET
expect_exit 0

# CONFIG_ prefix stripping: bare symbol should behave identically
check "bare symbol INET (no CONFIG_ prefix) exits 0"
run --dry-run check-kconfig INET
expect_exit 0

check "bare symbol INET output shows DRY (prefix was stripped correctly)"
expect_output_has "DRY"

# Live check — result depends on whether a kernel config is accessible
check "live check-kconfig exits 0 or 1 (system-dependent)"
run check-kconfig CONFIG_NET
expect_exit_any 0 1

check "live check-kconfig output shows a recognisable result"
expect_output_has "kconfig:\|no kernel config"

check "--dry-run check-kconfig with explicit expected value exits 0"
run --dry-run check-kconfig CONFIG_NET y
expect_exit 0

check "--dry-run check-kconfig with explicit expected value shows DRY"
expect_output_has "DRY"

# =============================================================================
#  SECTION 7 — check-deps
# =============================================================================
section "check-deps"

check "--dry-run check-deps ssl exits 0"
run --dry-run check-deps ssl
expect_exit 0

check "--dry-run check-deps ssl output shows DRY"
expect_output_has "DRY"

check "check-deps <nonexistent lib> exits 1"
run check-deps __no_such_lib_xyz_404__
expect_exit 1

check "check-deps <nonexistent lib> output shows NOT FOUND or FAIL"
expect_output_has "NOT FOUND\|FAIL"

check "--dry-run check-deps with multiple libraries exits 0"
run --dry-run check-deps ssl crypto
expect_exit 0

# =============================================================================
#  SECTION 8 — run-lib
# =============================================================================
section "run-lib"

# lib_aktualizr.sh has no lib_aktualizr_all function, so run_lib logs a
# warning but exits 0 because no check recorded a FAIL
check "run-lib foundries/lib_aktualizr.sh exits 0 (no _all function defined)"
run run-lib foundries/lib_aktualizr.sh
expect_exit 0

check "run-lib output warns about missing _all function"
expect_output_has "not found\|WARN"

check "run-lib output shows Results section"
expect_output_has "Results"

check "run-lib <nonexistent file> exits 1"
run run-lib __no_such_lib__.sh
expect_exit 1

check "run-lib <nonexistent file> output shows error message"
expect_output_has "not found\|Lib not found"

check "--dry-run run-lib exits 0"
run --dry-run run-lib foundries/lib_fioconfig.sh
expect_exit 0

check "--dry-run run-lib output shows DRY"
expect_output_has "DRY\|dry"

# --fn: call a specific function instead of the derived _all name
check "--fn lib_aktualizr_set_version run-lib exits 0"
run --fn lib_aktualizr_set_version run-lib foundries/lib_aktualizr.sh
expect_exit 0

check "--fn run-lib output shows Results section"
expect_output_has "Results"

check "--dry-run --fn lib_aktualizr_cmd run-lib exits 0"
run --dry-run --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh
expect_exit 0

check "--dry-run --fn lib_aktualizr_cmd output shows DRY"
expect_output_has "DRY"

# check_cmd() calls print_verbose before the existence test, so VERB appears
# even when aktualizr-lite is not installed on the host
check "--verbose --fn lib_aktualizr_cmd run-lib exits 0 or 1 (system-dependent)"
run --verbose --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh
expect_exit_any 0 1

check "--verbose --fn lib_aktualizr_cmd output shows VERB lines"
expect_output_has "VERB"

check "--filter fail --dry-run run-lib exits 0"
run --filter fail --dry-run run-lib foundries/lib_fioconfig.sh
expect_exit 0

check "--filter fail --dry-run run-lib hides OK results"
expect_output_not_has "\[ OK \]"

check "--no-color --dry-run run-lib exits 0"
run --no-color --dry-run run-lib foundries/lib_fioconfig.sh
expect_exit 0

check "--no-color --dry-run run-lib produces no ANSI escape sequences"
expect_no_ansi

check "--lib-dir override --dry-run run-lib exits 0"
run --lib-dir "${SCRIPT_DIR}/lib" --dry-run run-lib foundries/lib_fioconfig.sh
expect_exit 0

# Report file generation
run -r "${WORK_DIR}/run_lib_report.txt" \
    --dry-run \
    --fn lib_aktualizr_set_version \
    run-lib foundries/lib_aktualizr.sh

check "-r creates a report file after run-lib"
expect_file_exists "${WORK_DIR}/run_lib_report.txt"

check "-r report file contains the Foundries header"
expect_file_has "${WORK_DIR}/run_lib_report.txt" "Foundries Check Report"

check "-r report file contains PASS summary line"
expect_file_has "${WORK_DIR}/run_lib_report.txt" "PASS:"

# =============================================================================
#  SECTION 9 — run-all-libs
# =============================================================================
section "run-all-libs"

check "--dry-run run-all-libs exits 0"
run --dry-run run-all-libs
expect_exit 0

check "--dry-run run-all-libs output shows summary header"
expect_output_has "Run All Libs"

check "--dry-run run-all-libs output shows module count"
expect_output_has "module"

check "--quiet --dry-run run-all-libs exits 0"
run --quiet --dry-run run-all-libs
expect_exit 0

check "--filter fail --dry-run run-all-libs exits 0"
run --filter fail --dry-run run-all-libs
expect_exit 0

check "--no-color --dry-run run-all-libs exits 0"
run --no-color --dry-run run-all-libs
expect_exit 0

check "--no-color --dry-run run-all-libs produces no ANSI escape sequences"
expect_no_ansi

check "-r --dry-run run-all-libs exits 0"
run -r "${WORK_DIR}/all_libs_report.txt" \
    --dry-run \
    --fn lib_aktualizr_set_version \
    run-all-libs
expect_exit 0

# =============================================================================
#  SECTION 10 — run-all
# =============================================================================
section "run-all"

check "--dry-run run-all exits 0"
run --dry-run run-all
expect_exit 0

check "--dry-run run-all output shows summary header"
expect_output_has "Run All"

check "--dry-run run-all output shows profile count"
expect_output_has "profile"

check "--quiet --dry-run run-all exits 0"
run --quiet --dry-run run-all
expect_exit 0

check "--filter fail --dry-run run-all exits 0"
run --filter fail --dry-run run-all
expect_exit 0

check "--no-color --dry-run run-all exits 0"
run --no-color --dry-run run-all
expect_exit 0

check "--no-color --dry-run run-all produces no ANSI escape sequences"
expect_no_ansi

check "--profiles-dir override --dry-run run-all exits 0"
run --profiles-dir "${SCRIPT_DIR}/profiles" --dry-run run-all
expect_exit 0

# =============================================================================
#  SECTION 11 — load
# =============================================================================
section "load"

check "--dry-run load docker/docker.sh exits 0"
run --dry-run load docker/docker.sh
expect_exit 0

check "--dry-run load output identifies the profile"
expect_output_has "docker\|Profile\|Loading"

# Folder-name resolution: finds the first .sh inside profiles/docker/
check "--dry-run load docker (folder name) exits 0"
run --dry-run load docker
expect_exit 0

check "load <nonexistent profile> exits 1"
run load __no_such_profile_xyz__
expect_exit 1

check "load <nonexistent profile> output shows error message"
expect_output_has "not found\|Profile not found"

# Report file generation via load
run -r "${WORK_DIR}/load_report.txt" --dry-run load docker/docker.sh

check "-r creates a report file after load"
expect_file_exists "${WORK_DIR}/load_report.txt"

check "-r load report file contains the Foundries header"
expect_file_has "${WORK_DIR}/load_report.txt" "Foundries Check Report"

check "-r load report file contains PASS summary line"
expect_file_has "${WORK_DIR}/load_report.txt" "PASS:"

check "--filter fail --dry-run load exits 0"
run --filter fail --dry-run load docker/docker.sh
expect_exit 0

check "--no-color --dry-run load exits 0"
run --no-color --dry-run load docker/docker.sh
expect_exit 0

check "--no-color --dry-run load produces no ANSI escape sequences"
expect_no_ansi

# =============================================================================
#  SECTION 12 — Missing / invalid arguments
# =============================================================================
section "Missing / invalid arguments"

check "--report with no filename exits non-0"
run --report
expect_exit 2

check "--filter with no value exits non-0"
run --filter
expect_exit 2

check "--fn with no function name exits non-0"
run --fn
expect_exit 2

check "--profiles-dir with no path exits non-0"
run --profiles-dir
expect_exit 2

check "--lib-dir with no path exits non-0"
run --lib-dir
expect_exit 2

check "run-lib with no lib path exits non-0"
run run-lib
expect_exit 2

check "load with no profile path exits non-0"
run load
expect_exit 2

# =============================================================================
#  SECTION 13 — Option combinations
# =============================================================================
section "Option combinations"

# --no-color + --verbose together
check "--no-color --verbose check-cmd sh exits 0"
run --no-color --verbose check-cmd sh
expect_exit 0

check "--no-color --verbose output has no ANSI sequences"
expect_no_ansi

check "--no-color --verbose output still shows VERB lines"
expect_output_has "VERB"

# --quiet + --filter fail on a failing check
check "--quiet --filter fail on missing command exits 1"
run --quiet --filter fail check-cmd __nonexistent_xyz_404__
expect_exit 1

# --dry-run + --verbose
check "--dry-run --verbose check-kconfig exits 0"
run --dry-run --verbose check-kconfig CONFIG_NET
expect_exit 0

check "--dry-run --verbose output shows DRY marker"
expect_output_has "DRY"

# --dry-run + --no-color
check "--dry-run --no-color list-libs exits 0"
run --dry-run --no-color list-libs
expect_exit 0

check "--dry-run --no-color output has no ANSI sequences"
expect_no_ansi

# Comma-separated --filter values
check "--filter fail,warn check-cmd sh exits 0"
run --filter "fail,warn" check-cmd sh
expect_exit 0

check "--filter fail,warn hides OK results"
expect_output_not_has "\[ OK \]"

check "--filter fail,ok check-cmd sh exits 0"
run --filter "fail,ok" check-cmd sh
expect_exit 0

check "--filter fail,ok shows OK results"
expect_output_has "OK"

# Short-form aliases
check "-v is a short alias for --verbose"
run -v check-cmd sh
expect_exit 0

check "-v output shows VERB lines"
expect_output_has "VERB"

check "-q is a short alias for --quiet"
run -q check-cmd sh
expect_exit 0

check "-q suppresses OK output"
expect_output_not_has "\[ OK \]"

check "-r is a short alias for --report"
run -r "${WORK_DIR}/short_alias_report.txt" --dry-run run-lib foundries/lib_fioconfig.sh
expect_exit 0

check "-r creates the report file"
expect_file_exists "${WORK_DIR}/short_alias_report.txt"

# =============================================================================
#  Summary
# =============================================================================
printf '\n\033[1m%s\033[0m\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf 'PASS: \033[32m%d\033[0m   FAIL: \033[31m%d\033[0m   SKIP: \033[33m%d\033[0m\n' \
    "${PASS}" "${FAIL}" "${SKIP}"

if [ "${FAIL}" -eq 0 ]; then
    printf '\033[32mAll %d tests passed.\033[0m\n' "${PASS}"
    exit 0
else
    printf '\033[31m%d test(s) failed.  Re-run with -v for captured output.\033[0m\n' "${FAIL}"
    exit 1
fi
