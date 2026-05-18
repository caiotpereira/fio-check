#!/usr/bin/env sh
# =============================================================================
# test_fio_check.sh — Exercises all commands and options of fio-check.sh
#
# Usage:
#   cd /path/to/fio-check
#   ./test_fio_check.sh          # normal run
#   ./test_fio_check.sh -v       # verbose: show captured output on failure
#
# Exit: 0 = all passed, 1 = one or more failed
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIO="${SCRIPT_DIR}/fio-check.sh"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1

# ─── Counters and state ───────────────────────────────────────────────────────
_P=0; _F=0; _S=0
_OUT=""; _RC=0; _T=""

# ─── Temp workspace ───────────────────────────────────────────────────────────
_TMP="$(mktemp -d)"
trap 'rm -rf "${_TMP}"' EXIT INT TERM

# ─── ANSI check helper ───────────────────────────────────────────────────────
# cat -v converts ESC to the visible sequence ^[  — grep -F avoids regex issues
check_no_ansi() {
    if printf '%s\n' "${_OUT}" | cat -v | grep -qF '^['; then
        _fail "ANSI escape sequences found in output"
    else
        _ok
    fi
}

# ─── Mini framework ───────────────────────────────────────────────────────────
_section() { printf '\n\033[1m── %s ──\033[0m\n' "$*"; }
t()        { _T="$1"; }

run() {
    set +e
    _OUT=$("${FIO}" "$@" 2>&1)
    _RC=$?
    set -e
}

_ok()   { _P=$((_P+1)); printf '  \033[32m✓\033[0m %s\n' "${_T}"; }
_fail() {
    _F=$((_F+1))
    printf '  \033[31m✗\033[0m %s\n    └─ %s\n' "${_T}" "$1"
    if [ "${VERBOSE}" -eq 1 ]; then
        printf '%s\n' "${_OUT}" | head -15 | sed 's/^/      /'
    fi
}
_skip() { _S=$((_S+1)); printf '  \033[33m~\033[0m %s  [%s]\n' "${_T}" "$1"; }

expect_exit()    {
    [ "${_RC}" -eq "$1" ] && _ok || _fail "exit $1 expected, got ${_RC}"
}
expect_exit_any() {
    # Pass if exit code matches any of the given values (for system-dependent tests)
    local _found=0
    for _e in "$@"; do [ "${_RC}" -eq "${_e}" ] && _found=1 && break; done
    [ "${_found}" -eq 1 ] && _ok || _fail "exit in ($*) expected, got ${_RC}"
}
expect_contains() {
    printf '%s\n' "${_OUT}" | grep -q "$1" \
        && _ok \
        || _fail "output missing: $1"
}
expect_absent() {
    if printf '%s\n' "${_OUT}" | grep -q "$1"; then
        _fail "output should NOT contain: $1"
    else
        _ok
    fi
}
expect_file()     { [ -f "$1" ] && _ok || _fail "file missing: $1"; }
expect_file_has() { [ -f "$1" ] && grep -q "$2" "$1" && _ok || _fail "file '$1' missing: $2"; }

# ─── Sanity check ─────────────────────────────────────────────────────────────
_section "Preconditions"

t "fio-check.sh exists";     [ -f "${FIO}" ]     && _ok || _fail "not found: ${FIO}"
t "fio-check.sh executable"; [ -x "${FIO}" ]     && _ok || _fail "not executable: ${FIO}"

# ─── Help / Usage ─────────────────────────────────────────────────────────────
_section "Help / Usage"

t "help command exits 0";            run help;         expect_exit 0
t "help command shows USAGE";                          expect_contains "USAGE"
t "help command shows COMMANDS";                       expect_contains "COMMANDS"
t "help command shows OPTIONS";                        expect_contains "OPTIONS"

t "--help flag exits 0";             run --help;       expect_exit 0
t "--help shows tool name";                            expect_contains "fio-check"

t "-h flag exits 0";                 run -h;           expect_exit 0

t "no args shows usage, exits 0";   run;              expect_exit 0
t "no args shows USAGE";                               expect_contains "USAGE"

t "unknown command exits 1";        run bad-command;  expect_exit 1
t "unknown command shows error";                       expect_contains "Unknown"

t "unknown option exits 1";         run --bad-flag;   expect_exit 1

# ─── list-libs ────────────────────────────────────────────────────────────────
_section "list-libs"

t "list-libs exits 0";                  run list-libs;                        expect_exit 0
t "list-libs shows a lib file";                                               expect_contains "lib_docker"
t "list-libs shows foundries group";                                          expect_contains "foundries"

t "list-libs --verbose exits 0";        run --verbose list-libs;              expect_exit 0

t "list-libs --quiet exits 0";          run --quiet list-libs;                expect_exit 0

t "list-libs --no-color exits 0";       run --no-color list-libs;             expect_exit 0
t "list-libs --no-color has no ANSI";                                         check_no_ansi

t "list-libs --lib-dir valid exits 0";  run --lib-dir "${SCRIPT_DIR}/lib" list-libs;  expect_exit 0
t "list-libs --lib-dir valid shows lib";                                      expect_contains "lib_docker"

t "list-libs --lib-dir empty warns";    run --lib-dir "${_TMP}" list-libs;    expect_exit 0
t "list-libs --lib-dir empty output";                                         expect_contains "No lib modules\|not found"

t "list-libs --lib-dir missing warns";  run --lib-dir "/no_such_dir_xyz" list-libs; expect_exit 0

# ─── list-profiles ────────────────────────────────────────────────────────────
_section "list-profiles"

t "list-profiles exits 0";                    run list-profiles;                              expect_exit 0
t "list-profiles shows profile";                                                              expect_contains "docker\|foundries"

t "list-profiles --profiles-dir valid";       run --profiles-dir "${SCRIPT_DIR}/profiles" list-profiles; expect_exit 0
t "list-profiles --profiles-dir valid shows";                                                 expect_contains "docker"

t "list-profiles --profiles-dir empty warns"; run --profiles-dir "${_TMP}" list-profiles;    expect_exit 0
t "list-profiles --profiles-dir empty msg";                                                   expect_contains "No profiles\|not found"

t "list-profiles --no-color no ANSI";         run --no-color list-profiles;                  expect_exit 0
t "list-profiles --no-color output";                                                          check_no_ansi

# ─── check-cmd ────────────────────────────────────────────────────────────────
_section "check-cmd"

t "check-cmd sh exits 0";               run check-cmd sh;                        expect_exit 0
t "check-cmd sh shows OK";                                                       expect_contains "OK"

t "check-cmd multiple exists exits 0";  run check-cmd sh ls cat;                 expect_exit 0

t "check-cmd missing exits 1";          run check-cmd __nonexistent_xyz_404__;   expect_exit 1
t "check-cmd missing shows FAIL";                                                expect_contains "FAIL\|missing"

t "check-cmd one missing exits 1";      run check-cmd sh __nonexistent_xyz_404__; expect_exit 1

t "--dry-run check-cmd exits 0";        run --dry-run check-cmd sh;              expect_exit 0
t "--dry-run check-cmd shows DRY";                                               expect_contains "DRY"
t "--dry-run check-cmd no actual exec";                                          expect_absent "\[ OK \]"

t "--verbose check-cmd exits 0";        run --verbose check-cmd sh;              expect_exit 0
t "--verbose check-cmd shows VERB";                                              expect_contains "VERB"

t "--quiet check-cmd sh exits 0";       run --quiet check-cmd sh;               expect_exit 0
t "--quiet check-cmd no OK output";                                              expect_absent "\[ OK \]"

t "--no-color check-cmd exits 0";       run --no-color check-cmd sh;            expect_exit 0
t "--no-color check-cmd no ANSI";                                                check_no_ansi
t "--no-color check-cmd has OK text";                                            expect_contains "OK"

t "--filter ok check-cmd sh";           run --filter ok check-cmd sh;           expect_exit 0
t "--filter ok shows OK result";                                                 expect_contains "OK"

t "--filter fail check-cmd sh";         run --filter fail check-cmd sh;         expect_exit 0
t "--filter fail hides OK";                                                      expect_absent "\[ OK \]"

t "--filter fail check-cmd missing";    run --filter fail check-cmd __nonexistent_xyz_404__; expect_exit 1
t "--filter fail shows FAIL";                                                    expect_contains "FAIL\|missing"

t "--filter warn check-cmd sh";         run --filter warn check-cmd sh;         expect_exit 0

# ─── check-kconfig ────────────────────────────────────────────────────────────
_section "check-kconfig"

t "--dry-run check-kconfig exits 0";    run --dry-run check-kconfig CONFIG_NET; expect_exit 0
t "--dry-run check-kconfig shows DRY";                                          expect_contains "DRY"

t "--dry-run kconfig strips CONFIG_";   run --dry-run check-kconfig CONFIG_INET; expect_exit 0
t "bare symbol stripped (no CONFIG_)";  run --dry-run check-kconfig INET;       expect_exit 0
t "bare symbol DRY output";                                                      expect_contains "DRY"

t "check-kconfig live exits 0 or 1";   run check-kconfig CONFIG_NET;           expect_exit_any 0 1
t "check-kconfig live has result";                                              expect_contains "kconfig:\|no kernel config"

t "check-kconfig with expected value"; run --dry-run check-kconfig CONFIG_NET y; expect_exit 0
t "check-kconfig with expected DRY";                                            expect_contains "DRY"

# ─── check-deps ───────────────────────────────────────────────────────────────
_section "check-deps"

t "--dry-run check-deps exits 0";       run --dry-run check-deps ssl;           expect_exit 0
t "--dry-run check-deps shows DRY";                                             expect_contains "DRY"

t "check-deps nonexistent exits 1";     run check-deps __no_such_lib_xyz_404__; expect_exit 1
t "check-deps nonexistent shows FAIL";                                          expect_contains "NOT FOUND\|FAIL"

t "check-deps multiple --dry-run";      run --dry-run check-deps ssl crypto;    expect_exit 0

# ─── run-lib ──────────────────────────────────────────────────────────────────
_section "run-lib"

# lib_aktualizr_all does not exist in the lib, so run_lib warns but exits 0
t "run-lib exits 0 (no _all fn)";      run run-lib foundries/lib_aktualizr.sh; expect_exit 0
t "run-lib warns missing _all fn";                                              expect_contains "not found\|WARN"
t "run-lib shows Results section";                                              expect_contains "Results"

t "run-lib nonexistent exits 1";        run run-lib __no_such_lib__.sh;         expect_exit 1
t "run-lib nonexistent shows error";                                            expect_contains "not found\|Lib not found"

t "--dry-run run-lib exits 0";          run --dry-run run-lib foundries/lib_fioconfig.sh; expect_exit 0
t "--dry-run run-lib shows DRY";                                                expect_contains "DRY\|dry"

t "--fn with valid function exits 0";   run --fn lib_aktualizr_set_version run-lib foundries/lib_aktualizr.sh; expect_exit 0
t "--fn shows Results section";                                                 expect_contains "Results"

t "--dry-run --fn lib_aktualizr_cmd";   run --dry-run --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh; expect_exit 0
t "--dry-run --fn shows DRY";                                                   expect_contains "DRY"

t "--verbose run-lib shows VERB";       run --verbose --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh; expect_exit_any 0 1
t "--verbose run-lib VERB present";                                             expect_contains "VERB"

t "--filter fail --dry-run run-lib";    run --filter fail --dry-run run-lib foundries/lib_fioconfig.sh; expect_exit 0
t "--filter fail hides non-fail";                                               expect_absent "\[ OK \]"

t "--no-color run-lib no ANSI";         run --no-color --dry-run run-lib foundries/lib_fioconfig.sh; expect_exit 0
t "--no-color run-lib output clean";                                            check_no_ansi

t "run-lib --lib-dir override";         run --lib-dir "${SCRIPT_DIR}/lib" --dry-run run-lib foundries/lib_fioconfig.sh; expect_exit 0

t "-r report: run-lib creates file";    run -r "${_TMP}/rl_report.txt" --dry-run --fn lib_aktualizr_set_version run-lib foundries/lib_aktualizr.sh
t "-r report: file exists";             expect_file "${_TMP}/rl_report.txt"
t "-r report: has header";              expect_file_has "${_TMP}/rl_report.txt" "Foundries Check Report"
t "-r report: has PASS line";           expect_file_has "${_TMP}/rl_report.txt" "PASS:"

# ─── run-all-libs ─────────────────────────────────────────────────────────────
_section "run-all-libs"

t "--dry-run run-all-libs exits 0/1";   run --dry-run run-all-libs;             expect_exit_any 0 1
t "--dry-run run-all-libs shows summary";                                       expect_contains "Run All Libs"
t "--dry-run run-all-libs shows modules";                                       expect_contains "module"

t "--quiet --dry-run run-all-libs";     run --quiet --dry-run run-all-libs;     expect_exit_any 0 1

t "--filter fail --dry-run run-all-libs"; run --filter fail --dry-run run-all-libs; expect_exit_any 0 1

t "--no-color run-all-libs no ANSI";    run --no-color --dry-run run-all-libs;  expect_exit_any 0 1
t "--no-color run-all-libs output";                                             check_no_ansi

t "-r run-all-libs exit 0 or 1";
_rl_rep="${_TMP}/all_libs_report.txt"
run -r "${_rl_rep}" --dry-run --fn lib_aktualizr_set_version run-all-libs
expect_exit_any 0 1

# ─── run-all ──────────────────────────────────────────────────────────────────
_section "run-all"

t "--dry-run run-all exits 0/1";        run --dry-run run-all;                  expect_exit_any 0 1
t "--dry-run run-all shows summary";                                            expect_contains "Run All"
t "--dry-run run-all shows profile(s)";                                         expect_contains "profile"

t "--quiet --dry-run run-all";          run --quiet --dry-run run-all;          expect_exit_any 0 1

t "--filter fail --dry-run run-all";    run --filter fail --dry-run run-all;    expect_exit_any 0 1

t "--no-color run-all no ANSI";         run --no-color --dry-run run-all;       expect_exit_any 0 1
t "--no-color run-all output";                                                  check_no_ansi

t "--profiles-dir run-all override";    run --profiles-dir "${SCRIPT_DIR}/profiles" --dry-run run-all; expect_exit_any 0 1

# ─── load ─────────────────────────────────────────────────────────────────────
_section "load"

t "--dry-run load by path exits 0";     run --dry-run load docker/docker.sh;   expect_exit_any 0 1
t "--dry-run load shows profile name";                                          expect_contains "docker\|Profile\|Loading"

t "--dry-run load by folder name";      run --dry-run load docker;              expect_exit_any 0 1

t "load nonexistent profile exits 1";   run load __no_such_profile_xyz__;       expect_exit 1
t "load nonexistent shows error";                                               expect_contains "not found\|Profile not found"

t "-r load creates report file";        run -r "${_TMP}/load_report.txt" --dry-run load docker/docker.sh
t "-r load file exists";                expect_file "${_TMP}/load_report.txt"
t "-r load report has header";          expect_file_has "${_TMP}/load_report.txt" "Foundries Check Report"
t "-r load report has PASS line";       expect_file_has "${_TMP}/load_report.txt" "PASS:"

t "--filter fail load --dry-run";       run --filter fail --dry-run load docker/docker.sh; expect_exit_any 0 1

t "--no-color load no ANSI";            run --no-color --dry-run load docker/docker.sh; expect_exit_any 0 1
t "--no-color load output";                                                     check_no_ansi

# ─── Missing / invalid arguments ─────────────────────────────────────────────
_section "Missing / invalid arguments"

t "--report missing value exits non-0"; run --report;                          expect_exit 1
t "--filter missing value exits non-0"; run --filter;                          expect_exit 1
t "--fn missing value exits non-0";     run --fn;                              expect_exit 1
t "--profiles-dir missing exits non-0"; run --profiles-dir;                   expect_exit 1
t "--lib-dir missing exits non-0";      run --lib-dir;                         expect_exit 1
t "run-lib missing lib exits non-0";    run run-lib;                           expect_exit 1
t "load missing profile exits non-0";   run load;                              expect_exit 1

# ─── Option combinations ──────────────────────────────────────────────────────
_section "Option combinations"

t "--no-color --verbose check-cmd sh";  run --no-color --verbose check-cmd sh; expect_exit 0
t "combined: no ANSI codes";                                                    check_no_ansi
t "combined: has VERB";                                                         expect_contains "VERB"

t "--quiet --filter fail missing cmd";  run --quiet --filter fail check-cmd __nonexistent_xyz_404__; expect_exit 1

t "--dry-run --verbose check-kconfig";  run --dry-run --verbose check-kconfig CONFIG_NET; expect_exit 0
t "combined: has DRY";                                                          expect_contains "DRY"

t "--dry-run --no-color list-libs";     run --dry-run --no-color list-libs;    expect_exit 0
t "combined: no ANSI";                                                          check_no_ansi

t "--filter fail,warn check-cmd sh";    run --filter "fail,warn" check-cmd sh; expect_exit 0
t "--filter fail,warn hides OK";                                                expect_absent "\[ OK \]"

t "--filter fail,ok check-cmd sh";      run --filter "fail,ok" check-cmd sh;   expect_exit 0
t "--filter fail,ok shows OK";                                                  expect_contains "OK"

t "-v short for --verbose";             run -v check-cmd sh;                   expect_exit 0
t "-v shows VERB output";                                                       expect_contains "VERB"

t "-q short for --quiet";              run -q check-cmd sh;                    expect_exit 0
t "-q suppresses OK";                                                           expect_absent "\[ OK \]"

t "-r short for --report";             run -r "${_TMP}/short_r.txt" --dry-run run-lib foundries/lib_fioconfig.sh; expect_exit 0
t "-r created report file";            expect_file "${_TMP}/short_r.txt"

# ─── Summary ──────────────────────────────────────────────────────────────────
printf '\n\033[1m%s\033[0m\n' "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf 'PASS: \033[32m%d\033[0m   FAIL: \033[31m%d\033[0m   SKIP: \033[33m%d\033[0m\n' \
    "${_P}" "${_F}" "${_S}"

if [ "${_F}" -eq 0 ]; then
    printf '\033[32mAll %d tests passed.\033[0m\n' "${_P}"
    exit 0
else
    printf '\033[31m%d test(s) failed. Re-run with -v for output.\033[0m\n' "${_F}"
    exit 1
fi
