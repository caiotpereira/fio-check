#!/usr/bin/env sh
# =============================================================================
# test_fio_check.sh — Exercises all commands and options of fio-check.sh
#
# Usage:
#   cd /path/to/fio-check
#   ./test_fio_check.sh       # normal run
#   ./test_fio_check.sh -v    # verbose: show captured output on failure
#   FIO_SHELL=bash ./test_fio_check.sh   # run fio-check.sh under a given shell
#                                        # (default: its #! line)
#
# Exit: 0 = all tests passed, 1 = one or more failed
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FIO="${SCRIPT_DIR}/fio-check.sh"
FIO_SHELL="${FIO_SHELL:-}"
VERBOSE=0
[ "${1:-}" = "-v" ] && VERBOSE=1
ESC="$(printf '\033')"

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
#   FIO_SHELL (e.g. "bash", "busybox sh") is word-split on purpose.
run() {
    # shellcheck disable=SC2086
    OUTPUT=$(${FIO_SHELL} "${FIO}" "$@" 2>&1)
    EXIT_CODE=$?
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
        printf '%s\n' "${OUTPUT}" | head -n 15 | sed 's/^/      /'
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

# expect_no_shell_errors
#   Assert the captured output holds no shell error (syntax, missing applet,
#   unsupported option, non-integer test) from any of bash, dash, busybox.
expect_no_shell_errors() {
    local errs
    errs="$(printf '%s\n' "${OUTPUT}" | grep -E 'line [0-9]+: |^[^ ]*\.sh: [0-9]+: |command not found|: not found$|Illegal number|integer expression|unrecognized option|invalid option|[Ss]yntax error|bad substitution|applet not found')"
    if [ -z "${errs}" ]; then
        pass
    else
        fail "shell error: $(printf '%s\n' "${errs}" | head -n 1)"
    fi
}

# expect_dry_only
#   Assert a --dry-run listed checks ([DRY ]) without logging an OK or FAIL
#   result and without shell errors.
expect_dry_only() {
    if ! printf '%s\n' "${OUTPUT}" | grep -qF '[DRY ]'; then
        fail "no [DRY ] lines in dry-run output"
    elif printf '%s\n' "${OUTPUT}" | grep -qE '^ \[( OK |FAIL)\]'; then
        fail "dry-run logged a result: $(printf '%s\n' "${OUTPUT}" | grep -E '^ \[( OK |FAIL)\]' | head -n 1)"
    else
        expect_no_shell_errors
    fi
}

# expect_no_ansi
#   Assert the captured output contains no ANSI escape sequences.
#   Matches the raw ESC byte (busybox on target images has no cat -v).
expect_no_ansi() {
    if printf '%s\n' "${OUTPUT}" | grep -qF "${ESC}"; then
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
#  SECTION 3 — list — libs
# =============================================================================
section "list — libs"

check "list exits 0"
run list
expect_exit 0

check "list output shows lib_docker"
expect_output_has "lib_docker"

check "list output shows the components group"
expect_output_has "components"

# --verbose: list does not call check_* functions so no VERB lines
# are expected, but the flag must not cause a crash
check "list --verbose exits 0"
run --verbose list
expect_exit 0

check "list --quiet exits 0"
run --quiet list
expect_exit 0

check "list --no-color exits 0"
run --no-color list
expect_exit 0

check "list --no-color produces no ANSI escape sequences"
expect_no_ansi

check "list --lib-dir <valid path> exits 0"
run --lib-dir "${SCRIPT_DIR}/lib" list
expect_exit 0

check "list --lib-dir <valid path> shows lib_docker"
expect_output_has "lib_docker"

check "list --lib-dir <empty dir> exits 0 with warning"
run --lib-dir "${WORK_DIR}" list
expect_exit 0

check "list --lib-dir <empty dir> output mentions no modules found"
expect_output_has "No lib modules\|not found"

check "list --lib-dir <nonexistent path> exits 0"
run --lib-dir "/no_such_dir_xyz" list
expect_exit 0

# =============================================================================
#  SECTION 4 — list — profiles
# =============================================================================
section "list — profiles"

check "list exits 0"
run list
expect_exit 0

check "list output shows at least one profile"
expect_output_has "meta-foundries"

check "list shows the meta-foundries and meta-lmp profiles"
expect_output_has "meta-foundries/full-update"

check "list shows expectation sets and machine files per layer"
expect_output_has "expect: .*blacksail"

check "list does not list expectation files as profiles"
expect_output_not_has "expect/blacksail.sh"

check "list --profiles-dir <valid path> exits 0"
run --profiles-dir "${SCRIPT_DIR}/profiles" list
expect_exit 0

check "list --profiles-dir <valid path> shows meta-lmp profile"
expect_output_has "meta-lmp/lmp"

check "list --profiles-dir <empty dir> exits 0 with warning"
run --profiles-dir "${WORK_DIR}" list
expect_exit 0

check "list --profiles-dir <empty dir> output mentions no profiles found"
expect_output_has "No profiles\|not found"

check "list --no-color exits 0"
run --no-color list
expect_exit 0

check "list --no-color produces no ANSI escape sequences"
expect_no_ansi

# =============================================================================
#  SECTION 5 — check cmd
# =============================================================================
section "check cmd"

# Basic pass / fail
check "check cmd sh exits 0 (sh is always present)"
run check cmd sh
expect_exit 0

check "check cmd sh output shows OK"
expect_output_has "OK"

check "check cmd sh ls cat exits 0 (all present)"
run check cmd sh ls cat
expect_exit 0

check "check cmd <nonexistent> exits 1"
run check cmd __nonexistent_xyz_404__
expect_exit 1

check "check cmd <nonexistent> output shows FAIL or missing"
expect_output_has "FAIL\|missing"

check "check cmd sh <nonexistent> exits 1 when any command is missing"
run check cmd sh __nonexistent_xyz_404__
expect_exit 1

# --dry-run
check "--dry-run check cmd exits 0"
run --dry-run check cmd sh
expect_exit 0

check "--dry-run check cmd output shows DRY marker"
expect_output_has "DRY"

check "--dry-run check cmd does not log an OK result"
expect_output_not_has "\[ OK \]"

# --verbose
check "--verbose check cmd exits 0"
run --verbose check cmd sh
expect_exit 0

check "--verbose check cmd output shows VERB lines"
expect_output_has "VERB"

# --quiet
check "--quiet check cmd exits 0"
run --quiet check cmd sh
expect_exit 0

check "--quiet check cmd suppresses OK output"
expect_output_not_has "\[ OK \]"

# --no-color
check "--no-color check cmd exits 0"
run --no-color check cmd sh
expect_exit 0

check "--no-color check cmd produces no ANSI escape sequences"
expect_no_ansi

check "--no-color check cmd still shows OK as plain text"
expect_output_has "OK"

# --filter
check "--filter ok check cmd sh exits 0"
run --filter ok check cmd sh
expect_exit 0

check "--filter ok check cmd sh shows OK result"
expect_output_has "OK"

check "--filter fail check cmd sh exits 0"
run --filter fail check cmd sh
expect_exit 0

check "--filter fail check cmd sh hides OK result"
expect_output_not_has "\[ OK \]"

check "--filter fail check cmd <nonexistent> exits 1"
run --filter fail check cmd __nonexistent_xyz_404__
expect_exit 1

check "--filter fail check cmd <nonexistent> shows FAIL"
expect_output_has "FAIL\|missing"

check "--filter warn check cmd sh exits 0"
run --filter warn check cmd sh
expect_exit 0

# =============================================================================
#  SECTION 6 — check kconfig
# =============================================================================
section "check kconfig"

check "--dry-run check kconfig CONFIG_NET exits 0"
run --dry-run check kconfig CONFIG_NET
expect_exit 0

check "--dry-run check kconfig CONFIG_NET output shows DRY"
expect_output_has "DRY"

check "--dry-run check kconfig CONFIG_INET exits 0"
run --dry-run check kconfig CONFIG_INET
expect_exit 0

# CONFIG_ prefix stripping: bare symbol should behave identically
check "bare symbol INET (no CONFIG_ prefix) exits 0"
run --dry-run check kconfig INET
expect_exit 0

check "bare symbol INET output shows DRY (prefix was stripped correctly)"
expect_output_has "DRY"

check "live check kconfig CONFIG_NET exits 0"
run check kconfig CONFIG_NET
expect_exit 0

check "live check kconfig output shows a recognisable result"
expect_output_has "kconfig:\|no kernel config"

check "--dry-run check kconfig with explicit expected value exits 0"
run --dry-run check kconfig CONFIG_NET y
expect_exit 0

check "--dry-run check kconfig with explicit expected value shows DRY"
expect_output_has "DRY"

# =============================================================================
#  SECTION 7 — check lib
# =============================================================================
section "check lib"

check "--dry-run check lib ssl exits 0"
run --dry-run check lib ssl
expect_exit 0

check "--dry-run check lib ssl output shows DRY"
expect_output_has "DRY"

check "check lib <nonexistent lib> exits 1"
run check lib __no_such_lib_xyz_404__
expect_exit 1

check "check lib <nonexistent lib> output shows NOT FOUND or FAIL"
expect_output_has "NOT FOUND\|FAIL"

check "--dry-run check lib with multiple libraries exits 0"
run --dry-run check lib ssl crypto
expect_exit 0

# =============================================================================
#  SECTION 8 — run <lib>
# =============================================================================
section "run <lib>"

LIBFX="${WORK_DIR}/libfx"
mkdir -p "${LIBFX}"
cat > "${LIBFX}/lib_probe.sh" <<'EOF'
lib_probe_ok() { check_cmd sh; }
EOF

check "run <lib> without an _all function exits 0"
run --lib-dir "${LIBFX}" run probe
expect_exit 0

check "run <lib> without _all warns about the missing function"
expect_output_has "Function not found: lib_probe_all"

check "run output shows Results section"
expect_output_has "Results"

check "run <lib>:<function> exits 0"
run --lib-dir "${LIBFX}" run probe:ok
expect_exit 0

check "run <nonexistent file> exits 1"
run run __no_such_lib__.sh
expect_exit 1

check "run <nonexistent file> output shows error message"
expect_output_has "Not a profile or lib"

check "run accepts a component name (docker -> lib_docker_all)"
run --dry-run run docker
expect_output_has "lib_docker_all"

check "run accepts a lib file name"
run --dry-run run lib_docker.sh
expect_exit 0

check "run accepts components/<lib>"
run --dry-run run components/lib_docker.sh
expect_exit 0

check "run <lib>:<function> calls lib_<lib>_<function>"
run --dry-run run docker:daemon_config
expect_output_has "lib_docker_daemon_config"

check "run <lib>:lib_<full name> calls that function"
run --dry-run run docker:lib_docker_version
expect_output_has "lib_docker_version"

check "options are accepted after the command"
run run docker:cmds --dry-run --no-color
expect_output_has "DRY"

check "run with no target exits 2"
run run
expect_exit 2

check "run with two targets exits 2"
run run docker fioconfig
expect_exit 2

check "run <lib>:<function> --expect <layer>/<set> loads the set"
run --dry-run run docker:daemon_config --expect meta-foundries/wrynose
expect_output_has "expect/wrynose.sh"

check "a bare --expect name found in several layers is rejected for a lib"
run --dry-run run docker:daemon_config --expect wrynose
expect_output_has "exists in several layers"

run -r "${WORK_DIR}/run_lib_report.txt" --dry-run run lib_fioconfig.sh
check "-r creates a report file after run"
expect_file_exists "${WORK_DIR}/run_lib_report.txt"
check "-r report file contains the Foundries header"
expect_file_has "${WORK_DIR}/run_lib_report.txt" "Foundries Check Report"
check "-r report file contains the PASS/FAIL/WARN/SKIP line"
expect_file_has "${WORK_DIR}/run_lib_report.txt" "PASS: .*WARN: "

# Every lib: --dry-run lists its checks without executing or logging results,
# and a live run raises no shell error in this shell.
for lib in "${SCRIPT_DIR}"/lib/components/lib_*.sh; do
    name="$(basename "${lib}")"

    check "--dry-run run ${name} exits 0"
    run --dry-run run "${name}"
    expect_exit 0

    check "--dry-run run ${name} lists checks and logs no result"
    expect_dry_only

    check "run ${name} raises no shell error"
    run run "${name}"
    expect_no_shell_errors
done

# =============================================================================
#  SECTION 9 — run <profile>
# =============================================================================
section "run <profile>"

# A fixture profile tree exercises the runner without host dependencies
PROFX="${WORK_DIR}/profx"
mkdir -p "${PROFX}/demo/expect"
cat > "${PROFX}/demo/demo.sh" <<'EOF'
: "${FIOCHECK_DEMO_CMD:=sh}"
fiocheck_pre_hook()  { log_info "pre_hook: demo"; }
fiocheck_run()       { fiocheck_req DEMO-1 "Demo"; check_cmd "${FIOCHECK_DEMO_CMD}"; }
fiocheck_post_hook() { log_info "post_hook: demo"; }
EOF
printf ': "${FIOCHECK_DEMO_CMD:=__no_such_cmd__}"\n' > "${PROFX}/demo/expect/broken.sh"

check "run <fixture> exits 0"
run --profiles-dir "${PROFX}" run demo/demo.sh
expect_exit 0

check "run output identifies the profile"
expect_output_has "Loading Profile: demo"

check "run calls fiocheck_pre_hook"
expect_output_has "pre_hook: demo"

check "run calls fiocheck_post_hook"
expect_output_has "post_hook: demo"

check "run tags results with fiocheck_req"
expect_output_has "\\[DEMO-1\\] Command exists: sh"

check "an expectation set overrides the profile default"
run --profiles-dir "${PROFX}" --expect broken run demo/demo.sh
expect_exit 1

check "run <folder name> resolves the profile"
run --profiles-dir "${PROFX}" run demo
expect_exit 0

check "run <layer>/<name> without .sh resolves the profile"
run --dry-run run meta-foundries/os-update
expect_exit 0

check "run <nonexistent profile> exits 1"
run run __no_such_profile_xyz__
expect_exit 1

check "run <nonexistent profile> output shows error message"
expect_output_has "Not a profile or lib"

run -r "${WORK_DIR}/load_report.txt" --profiles-dir "${PROFX}" run demo
check "-r run report file contains the Foundries header"
expect_file_has "${WORK_DIR}/load_report.txt" "Foundries Check Report"
check "-r run report file records the mode"
expect_file_has "${WORK_DIR}/load_report.txt" "Mode      : dev"
check "-r run report file carries the requirement tag"
expect_file_has "${WORK_DIR}/load_report.txt" "DEMO-1"

for p in meta-foundries/os-update meta-foundries/full-update meta-lmp/lmp; do
    check "--dry-run run ${p} exits 0"
    run --dry-run run "${p}"
    expect_exit 0

    check "--dry-run run ${p} lists checks and logs no result"
    expect_dry_only
done

check "--expect <unknown> exits 1"
run --expect __nope__ run meta-foundries/os-update
expect_exit 1

check "--expect <unknown> lists the layer's sets"
expect_output_has "Available: meta-foundries/blacksail meta-foundries/wrynose"

check "--machine <unknown> exits 1"
run --machine __nope__ run meta-foundries/os-update
expect_exit 1

check "--expect <name> is reported in the run header"
run --dry-run --expect blacksail run meta-foundries/os-update
expect_output_has "Expect: blacksail"

# =============================================================================
#  SECTION 10 — Static profiles (--root)
#
#  The same profiles a device runs, checked against generated rootfs trees:
#  conforming images pass, every injected fault fails with its requirement tag.
# =============================================================================
section "Static profiles (--root)"

FX="${WORK_DIR}/fx"
mkdir -p "${FX}"
mkfx() { sh "${SCRIPT_DIR}/tests/fixtures/make-rootfs.sh" "$@" >/dev/null 2>&1; }

# srun <fixture> <expect> <profile> [options...]
srun() {
    local fx="$1" ex="$2" pr="$3"
    shift 3
    run --no-color --root "${FX}/${fx}" --kconfig "${FX}/${fx}.kconfig" --expect "${ex}" "$@" run "${pr}"
}

mkfx "${FX}/os"   foundries-os
mkfx "${FX}/full" foundries-full
mkfx "${FX}/lmp"  lmp
mkfx "${FX}/prod" foundries-full qemux86-64 production

check "fixture rootfs were generated"
if [ -d "${FX}/os/usr/bin" ] && [ -d "${FX}/full/usr/bin" ] && [ -f "${FX}/lmp.kconfig" ]; then pass; else fail "make-rootfs.sh failed"; fi

check "os-update passes on an OS Update rootfs"
srun os blacksail meta-foundries/os-update --machine qemux86-64
expect_exit 0

check "os-update tags results with requirement IDs"
expect_output_has "\[FR-08\]"

check "--root mode skips runtime checks"
expect_output_has "needs a running system"

check "full-update passes on a Full Update rootfs"
srun full blacksail meta-foundries/full-update --machine qemux86-64
expect_exit 0

check "full-update checks the daemon.json entries from the expectation set"
expect_output_has "max-concurrent-downloads=3"

check "os-update fails on a Full Update rootfs (FR-01)"
srun full blacksail meta-foundries/os-update
expect_exit 1

check "os-update reports the container stack as FR-01"
expect_output_has "\[FR-01\] Command must be absent: docker"

check "meta-lmp/lmp passes on an LmP rootfs (expect wrynose)"
srun lmp wrynose meta-lmp/lmp
expect_exit 0

check "meta-lmp/lmp passes on an LmP rootfs (expect v97)"
srun lmp v97 meta-lmp/lmp
expect_exit 0

check "a machine file sets the hardware id: mismatch fails"
srun os blacksail meta-foundries/os-update --machine uno-q
expect_exit 1

check "hardware id mismatch names both values"
expect_output_has "Hardware ID: qemux86-64 — expected uno-q"

check "the environment overrides the machine file"
FIOCHECK_AKLITE_HARDWARE_ID=qemux86-64; export FIOCHECK_AKLITE_HARDWARE_ID
srun os blacksail meta-foundries/os-update --machine uno-q
unset FIOCHECK_AKLITE_HARDWARE_ID
expect_exit 0

check "a substitute SOTA_CLIENT is checked through the variable (FR-06)"
FIOCHECK_SOTA_CLIENT=custom-sota-client; export FIOCHECK_SOTA_CLIENT
srun os blacksail meta-foundries/os-update
unset FIOCHECK_SOTA_CLIENT
expect_output_has "Command missing: custom-sota-client"

check "the legacy lmp-device-register name fails on meta-foundries (D-18)"
cp -R "${FX}/os" "${FX}/legacy"; cp "${FX}/os.kconfig" "${FX}/legacy.kconfig"
printf '#!/bin/sh\n' > "${FX}/legacy/usr/bin/lmp-device-register"
srun legacy blacksail meta-foundries/os-update
expect_output_has "Command must be absent: lmp-device-register"

check "/var/sota with the wrong mode fails"
cp -R "${FX}/os" "${FX}/mode"; cp "${FX}/os.kconfig" "${FX}/mode.kconfig"
chmod 0755 "${FX}/mode/var/sota"
srun mode blacksail meta-foundries/os-update
expect_output_has "Mode: /var/sota = 755 — expected 700"

check "a disabled unit fails where enabled is required"
cp -R "${FX}/os" "${FX}/disabled"; cp "${FX}/os.kconfig" "${FX}/disabled.kconfig"
rm -f "${FX}/disabled/etc/systemd/system/multi-user.target.wants/fioconfig.service"
srun disabled blacksail meta-foundries/os-update
expect_output_has "unit: fioconfig.service enable=disabled — expected enabled"

check "a masked unit fails"
cp -R "${FX}/os" "${FX}/masked"; cp "${FX}/os.kconfig" "${FX}/masked.kconfig"
ln -sf /dev/null "${FX}/masked/etc/systemd/system/aktualizr-lite.service"
srun masked blacksail meta-foundries/os-update
expect_output_has "unit: aktualizr-lite.service is masked"

check "a static unit is reported as static"
expect_output_has "unit: ostree-remount.service enable=static"

check "daemon.json drift fails"
cp -R "${FX}/full" "${FX}/drift"; cp "${FX}/full.kconfig" "${FX}/drift.kconfig"
printf '{\n  "storage-driver": "vfs",\n  "max-concurrent-downloads": 3\n}\n' \
    > "${FX}/drift/usr/lib/docker/daemon.json"
srun drift blacksail meta-foundries/full-update
expect_output_has "expected storage-driver=overlay2"

check "a disabled kernel option fails"
grep -v '^CONFIG_VETH=' "${FX}/full.kconfig" > "${FX}/novet.kconfig"
run --no-color --root "${FX}/full" --kconfig "${FX}/novet.kconfig" --expect blacksail run meta-foundries/full-update
expect_output_has "kconfig: CONFIG_VETH is not enabled"

check "a missing kernel config is a warning, not a pass"
run --no-color --root "${FX}/full" --expect blacksail run meta-foundries/full-update
expect_output_has "no kernel config found"

check "a missing kernel config fails with --warn-as-fail"
run --no-color --warn-as-fail --root "${FX}/full" --expect blacksail run meta-foundries/full-update
expect_exit 1

check "--mode production fails on a development rootfs (SR-13)"
srun full blacksail meta-foundries/full-update --mode production
expect_output_has "\[SR-13\] Credentials: development user"

check "--mode production passes on a production rootfs"
srun prod blacksail meta-foundries/full-update --mode production
expect_exit 0

check "--root <nonexistent> exits 2"
run --root "${WORK_DIR}/__none__" run meta-foundries/os-update
expect_exit 2

check "--mode <invalid> exits 2"
run --mode staging run meta-foundries/os-update
expect_exit 2

# =============================================================================
#  SECTION 11 — Core checks
# =============================================================================
section "Core checks"

STUB="${WORK_DIR}/stub"
mkdir -p "${STUB}"
printf '#!/bin/sh\necho "Fio tool version 29.7.2, build abc1234"\n' > "${STUB}/fiover"
chmod 0755 "${STUB}/fiover"
cat > "${LIBFX}/lib_core.sh" <<'EOF'
lib_core_ver_ok()      { check_cmd_version fiover 20.0.0; }
lib_core_ver_old()     { check_cmd_version fiover 99.0.0; }
lib_core_ver_minor()   { check_cmd_version fiover 29.10.0; }
lib_core_ver_exact()   { check_cmd_version fiover abc1234 --version '[0-9a-f]{7}' true; }
lib_core_ver_report()  { check_cmd_version fiover ""; }
lib_core_ver_missing() { check_cmd_version __no_such_cmd__ 1.0; }
lib_core_cmp() {
    _compare_versions 1.10 1.9;     [ $? -eq 1 ] && log_ok "cmp 1.10 > 1.9"     || log_fail "cmp 1.10 > 1.9"
    _compare_versions 2.0-rc1 2.0;  [ $? -eq 0 ] && log_ok "cmp 2.0-rc1 = 2.0"  || log_fail "cmp 2.0-rc1 = 2.0"
    _compare_versions 3 3.0.1;      [ $? -eq 2 ] && log_ok "cmp 3 < 3.0.1"      || log_fail "cmp 3 < 3.0.1"
}
lib_core_lib_missing() { check_lib_dependency zz_no_such_lib_xyz; }
lib_core_lib_prefix()  { check_lib_dependency libostree-1; check_lib_dependency ostree-1; }
lib_core_sysctl_dry()  { check_sysctl net.ipv4.ip_forward 1; }
EOF

# crun <fn> [options...] — call one lib_core function with the stubs on PATH
crun() {
    local fn="$1"
    shift
    local save="${PATH}"
    PATH="${STUB}:${PATH}"; export PATH
    run --no-color --lib-dir "${LIBFX}" "$@" run "core:${fn}"
    PATH="${save}"; export PATH
}

check "check_cmd_version passes a satisfied minimum"
crun lib_core_ver_ok
expect_exit 0

check "check_cmd_version fails a version below the minimum"
crun lib_core_ver_old
expect_exit 1

check "check_cmd_version compares segments numerically (29.7 < 29.10)"
crun lib_core_ver_minor
expect_exit 1

check "check_cmd_version raises no shell error"
expect_no_shell_errors

check "check_cmd_version matches an exact commit"
crun lib_core_ver_exact
expect_exit 0

check "check_cmd_version without expectation reports only"
crun lib_core_ver_report
expect_output_has "29.7.2 (not enforced)"

check "check_cmd_version on a missing command fails cleanly"
crun lib_core_ver_missing
expect_output_has "command missing"

check "check_cmd_version on a missing command raises no shell error"
expect_no_shell_errors

check "_compare_versions orders versions"
crun lib_core_cmp
expect_exit 0

check "check_lib_dependency fails a missing library"
crun lib_core_lib_missing
expect_exit 1

check "check_lib_dependency accepts names with and without lib prefix (--root)"
crun lib_core_lib_prefix --root "${FX}/os"
expect_exit 0

check "--dry-run check_sysctl does not run sysctl"
crun lib_core_sysctl_dry --dry-run
expect_dry_only

# =============================================================================
#  SECTION 12 — Portability lint
# =============================================================================
section "Portability lint"

LINT_FILES="${SCRIPT_DIR}/fio-check.sh ${SCRIPT_DIR}/lib ${SCRIPT_DIR}/profiles \
${SCRIPT_DIR}/tools ${SCRIPT_DIR}/tests/fixtures"

# lint <description> <ERE> — fail when any shell file matches
lint() {
    check "$1"
    # shellcheck disable=SC2086
    local hits; hits="$(grep -rnE "$2" ${LINT_FILES} 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')"
    if [ -z "${hits}" ]; then
        pass
    else
        fail "$(printf '%s\n' "${hits}" | head -n 3 | tr '\n' ' ')"
    fi
}

lint "no legacy head/tail -N (OE busybox rejects it)" '(head|tail) -[0-9]'
lint "no cat -v (not in OE busybox)"                  'cat -v'
lint "no bash [[ ]] tests"                            '\[\[ '
lint "no bash 'source' builtin"                       '(^|[;&|[:space:]])source [^-]'
lint "no 'function' keyword"                          '^[[:space:]]*function [a-z_]'
lint "no undefined _dry_print helper"                 '_dry_print'
lint "no GNU-only sed -i / grep -P / sort -V"         'sed -i|grep -[a-zA-Z]*P|sort -V'


# =============================================================================
#  SECTION 13 — Missing / invalid arguments
# =============================================================================
section "Missing / invalid arguments"

check "--report with no filename exits non-0"
run --report
expect_exit 2

check "--filter with no value exits non-0"
run --filter
expect_exit 2

check "the removed --fn option is rejected"
run --fn x run docker
expect_exit 1

check "--profiles-dir with no path exits non-0"
run --profiles-dir
expect_exit 2

check "--lib-dir with no path exits non-0"
run --lib-dir
expect_exit 2

check "run with no lib path exits non-0"
run run
expect_exit 2

check "run with no profile path exits non-0"
run run
expect_exit 2

# =============================================================================
#  SECTION 14 — Option combinations
# =============================================================================
section "Option combinations"

# --no-color + --verbose together
check "--no-color --verbose check cmd sh exits 0"
run --no-color --verbose check cmd sh
expect_exit 0

check "--no-color --verbose output has no ANSI sequences"
expect_no_ansi

check "--no-color --verbose output still shows VERB lines"
expect_output_has "VERB"

# --quiet + --filter fail on a failing check
check "--quiet --filter fail on missing command exits 1"
run --quiet --filter fail check cmd __nonexistent_xyz_404__
expect_exit 1

# --dry-run + --verbose
check "--dry-run --verbose check kconfig exits 0"
run --dry-run --verbose check kconfig CONFIG_NET
expect_exit 0

check "--dry-run --verbose output shows DRY marker"
expect_output_has "DRY"

# --dry-run + --no-color
check "--dry-run --no-color list exits 0"
run --dry-run --no-color list
expect_exit 0

check "--dry-run --no-color output has no ANSI sequences"
expect_no_ansi

# Comma-separated --filter values
check "--filter fail,warn check cmd sh exits 0"
run --filter "fail,warn" check cmd sh
expect_exit 0

check "--filter fail,warn hides OK results"
expect_output_not_has "\[ OK \]"

check "--filter fail,ok check cmd sh exits 0"
run --filter "fail,ok" check cmd sh
expect_exit 0

check "--filter fail,ok shows OK results"
expect_output_has "OK"

# Short-form aliases
check "-v is a short alias for --verbose"
run -v check cmd sh
expect_exit 0

check "-v output shows VERB lines"
expect_output_has "VERB"

check "-q is a short alias for --quiet"
run -q check cmd sh
expect_exit 0

check "-q suppresses OK output"
expect_output_not_has "\[ OK \]"

check "-r is a short alias for --report"
run -r "${WORK_DIR}/short_alias_report.txt" --dry-run run lib_fioconfig.sh
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
    if [ "${VERBOSE}" -eq 0 ]; then
        printf '\033[31m%d test(s) failed.  Re-run with -v for captured output.\033[0m\n' "${FAIL}"
    else
        printf '\033[31m%d test(s) failed.\033[0m\n' "${FAIL}"
    fi
    exit 1
fi
