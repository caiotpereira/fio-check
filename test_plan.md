# Test Plan — fio-check

| | |
|---|---|
| **Document** | test_plan.md |
| **Scripts** | test_fio_check.sh, tests/validate-profiles.sh, tests/run-docker-tests.sh |
| **Tool under test** | fio-check.sh 0.2.1 |
| **Date** | 2026-11-02 |
| **Test cases** | 207 in test_fio_check.sh (247 executed: some run once per lib or profile), plus 14 profile combinations |

---

## Overview

### Purpose

Verify that fio-check reports correctly. That means checking:
- every command, option and error path behaves as documented;
- every check helper gives the right verdict, passing what conforms and
  failing what doesn't;
- every profile passes on an image that matches its layer and fails, with
  the right requirement tag, on each injected fault;
- fio-check runs standalone, and finds libs and profiles in added
  directories in search-path order;
- all of this holds under busybox ash (GPLv3-free images), dash and bash.

The test object here is fio-check itself. In ISTQB terms, `test_fio_check.sh`
is component and component-integration testing of fio-check, and
`tests/validate-profiles.sh` is regression testing of its profiles and
expectation sets. For what fio-check tests *on an image*, see the README.

This plan maps 1-to-1 to `test_fio_check.sh`: section N and case M are
`TC-N.M`, in script order. A test name in the script output finds its row
here.

### How to run

```sh
./test_fio_check.sh                     # fio-check executed by its #! line
./test_fio_check.sh -v                  # show captured output on failure
FIO_SHELL=dash ./test_fio_check.sh      # fio-check executed by a given shell
tests/validate-profiles.sh [-v]         # profile matrix (section P)
tests/run-docker-tests.sh               # both, in every environment (section E)
```

Exit code `0` = all passed, `1` = one or more failed.

### Environments (E)

`tests/run-docker-tests.sh` runs the suite and the profile matrix in each
environment, with the repository mounted read-only.

| Target | Userland | fio-check runs under |
|---|---|---|
| busybox-oe | scratch image, static busybox 1.38.0 built with the OE-core busybox configuration | busybox ash |
| busybox-lmp | busybox-oe plus the meta-lmp busybox fragments | busybox ash |
| bash | Debian trixie | bash |
| dash | Debian trixie | dash |

The busybox targets match a GPLv3-free meta-foundries or meta-lmp image: no
bash, no GNU tools, and the options OE-core disables (legacy `head -N`,
`cat -v`). Results that depend on the host, such as live runs of libs on a
build machine, are asserted as `exit 0|1`. Deterministic results come from
fixtures.

### Fixtures

| Fixture | Built by | Used in |
|---|---|---|
| Rootfs trees (foundries-os, foundries-full, lmp; dev and production users) with a matching `.kconfig` | `tests/fixtures/make-rootfs.sh` | Section 10, section P |
| Copies of a rootfs with one injected fault (legacy binary, wrong mode, disabled or masked unit, `daemon.json` drift, kernel option removed) | Section 10 | Section 10 |
| Probe libs `lib_probe.sh`, `lib_core.sh` | Sections 8 and 11 | Sections 8 and 11 |
| Stub command `fiover` (prints `Fio tool version 29.7.2, build abc1234`) | Section 11 | Section 11 |
| Demo profile tree with an expectation set | Section 9 | Section 9 |
| Standalone copy of `fio-check.sh` (no `lib/`, no `profiles/`), and an external tree with a product profile, an expectation set and two overriding lib directories | Section 12 | Section 12 |

### Notation

| Token | Meaning |
|---|---|
| `exit N` | fio-check must exit with code N |
| `exit 0\|1` | either code (depends on the host) |
| `output: <text>` | combined stdout+stderr must match the text (grep basic regex) |
| `absent: <text>` | combined stdout+stderr must not match the text |
| `file: <path>` | the file must exist |
| `file-has: <text>` | the file must match the text |
| no ANSI escapes | output holds no ESC byte |
| no shell error | output holds no shell error from bash, dash or busybox (syntax, missing command or applet, unsupported option, non-integer test) |
| dry-run only | output lists `[DRY ]` checks, logs no OK or FAIL, and has no shell error |
| ↑ same run | asserts on the output of the command in the row above |
| *(for each `x`)* | the case runs once per lib (`lib/components/lib_*.sh`) or per profile |

`srun <fixture> <set> <profile> [opts]` is `fio-check.sh --no-color --root
<fixture> --kconfig <fixture>.kconfig --expect <set> [opts] run <profile>`.
`crun <fn> [opts]` runs `core:<fn>` from the probe lib with the stub command
on `PATH`. `arun [args]` runs the standalone copy of `fio-check.sh`.

---

## Section 1 — Preconditions

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-1.1 | fio-check.sh exists | `[ -f "${FIO}" ]` | true |
| TC-1.2 | fio-check.sh is executable | `[ -x "${FIO}" ]` | true |

## Section 2 — Help / Usage

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-2.1 | help command exits 0 | `fio-check.sh help` | `exit 0` |
| TC-2.2 | help command shows USAGE section | ↑ same run | `output: "USAGE"` |
| TC-2.3 | help command shows COMMANDS section | ↑ same run | `output: "COMMANDS"` |
| TC-2.4 | help command shows OPTIONS section | ↑ same run | `output: "OPTIONS"` |
| TC-2.5 | --help flag exits 0 | `fio-check.sh --help` | `exit 0` |
| TC-2.6 | --help flag shows tool name | ↑ same run | `output: "fio-check"` |
| TC-2.7 | -h short flag exits 0 | `fio-check.sh -h` | `exit 0` |
| TC-2.8 | no arguments shows usage and exits 0 | `fio-check.sh` | `exit 0` |
| TC-2.9 | no arguments output contains USAGE | ↑ same run | `output: "USAGE"` |
| TC-2.10 | unknown command exits 1 | `fio-check.sh bad-command` | `exit 1` |
| TC-2.11 | unknown command shows error message | ↑ same run | `output: "Unknown"` |
| TC-2.12 | unknown option exits 1 | `fio-check.sh --bad-flag` | `exit 1` |

## Section 3 — list — libs

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-3.1 | list exits 0 | `fio-check.sh list` | `exit 0` |
| TC-3.2 | list output shows lib_docker | ↑ same run | `output: "lib_docker"` |
| TC-3.3 | list output shows the components group | ↑ same run | `output: "components"` |
| TC-3.4 | list --verbose exits 0 | `fio-check.sh --verbose list` | `exit 0` |
| TC-3.5 | list --quiet exits 0 | `fio-check.sh --quiet list` | `exit 0` |
| TC-3.6 | list --no-color exits 0 | `fio-check.sh --no-color list` | `exit 0` |
| TC-3.7 | list --no-color produces no ANSI escape sequences | ↑ same run | no ANSI escapes |
| TC-3.8 | list --lib-dir <valid path> exits 0 | `fio-check.sh --lib-dir "${SCRIPT_DIR}/lib" list` | `exit 0` |
| TC-3.9 | list --lib-dir <valid path> shows lib_docker | ↑ same run | `output: "lib_docker"` |
| TC-3.10 | list --lib-dir <empty dir> exits 0 with warning | `fio-check.sh --lib-dir "${WORK_DIR}" list` | `exit 0` |
| TC-3.11 | list --lib-dir <empty dir> output mentions no modules found | ↑ same run | `output: "No lib modules\|not found"` |
| TC-3.12 | list --lib-dir <nonexistent path> exits 0 | `fio-check.sh --lib-dir "/no_such_dir_xyz" list` | `exit 0` |

## Section 4 — list — profiles

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-4.1 | list exits 0 | `fio-check.sh list` | `exit 0` |
| TC-4.2 | list output shows at least one profile | ↑ same run | `output: "meta-foundries"` |
| TC-4.3 | list shows the meta-foundries and meta-lmp profiles | ↑ same run | `output: "meta-foundries/full-update"` |
| TC-4.4 | list shows expectation sets and machine files per layer | ↑ same run | `output: "expect: .*blacksail"` |
| TC-4.5 | list does not list expectation files as profiles | ↑ same run | `absent: "expect/blacksail.sh"` |
| TC-4.6 | list --profiles-dir <valid path> exits 0 | `fio-check.sh --profiles-dir "${SCRIPT_DIR}/profiles" list` | `exit 0` |
| TC-4.7 | list --profiles-dir <valid path> shows meta-lmp profile | ↑ same run | `output: "meta-lmp/lmp"` |
| TC-4.8 | list --profiles-dir <empty dir> exits 0 with warning | `fio-check.sh --profiles-dir "${WORK_DIR}" list` | `exit 0` |
| TC-4.9 | list --profiles-dir <empty dir> output mentions no profiles found | ↑ same run | `output: "No profiles\|not found"` |
| TC-4.10 | list --no-color exits 0 | `fio-check.sh --no-color list` | `exit 0` |
| TC-4.11 | list --no-color produces no ANSI escape sequences | ↑ same run | no ANSI escapes |

## Section 5 — check cmd

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-5.1 | check cmd sh exits 0 (sh is always present) | `fio-check.sh check cmd sh` | `exit 0` |
| TC-5.2 | check cmd sh output shows OK | ↑ same run | `output: "OK"` |
| TC-5.3 | check cmd sh ls cat exits 0 (all present) | `fio-check.sh check cmd sh ls cat` | `exit 0` |
| TC-5.4 | check cmd <nonexistent> exits 1 | `fio-check.sh check cmd __nonexistent_xyz_404__` | `exit 1` |
| TC-5.5 | check cmd <nonexistent> output shows FAIL or missing | ↑ same run | `output: "FAIL\|missing"` |
| TC-5.6 | check cmd sh <nonexistent> exits 1 when any command is missing | `fio-check.sh check cmd sh __nonexistent_xyz_404__` | `exit 1` |
| TC-5.7 | --dry-run check cmd exits 0 | `fio-check.sh --dry-run check cmd sh` | `exit 0` |
| TC-5.8 | --dry-run check cmd output shows DRY marker | ↑ same run | `output: "DRY"` |
| TC-5.9 | --dry-run check cmd does not log an OK result | ↑ same run | `absent: "\[ OK \]"` |
| TC-5.10 | --verbose check cmd exits 0 | `fio-check.sh --verbose check cmd sh` | `exit 0` |
| TC-5.11 | --verbose check cmd output shows VERB lines | ↑ same run | `output: "VERB"` |
| TC-5.12 | --quiet check cmd exits 0 | `fio-check.sh --quiet check cmd sh` | `exit 0` |
| TC-5.13 | --quiet check cmd suppresses OK output | ↑ same run | `absent: "\[ OK \]"` |
| TC-5.14 | --no-color check cmd exits 0 | `fio-check.sh --no-color check cmd sh` | `exit 0` |
| TC-5.15 | --no-color check cmd produces no ANSI escape sequences | ↑ same run | no ANSI escapes |
| TC-5.16 | --no-color check cmd still shows OK as plain text | ↑ same run | `output: "OK"` |
| TC-5.17 | --filter ok check cmd sh exits 0 | `fio-check.sh --filter ok check cmd sh` | `exit 0` |
| TC-5.18 | --filter ok check cmd sh shows OK result | ↑ same run | `output: "OK"` |
| TC-5.19 | --filter fail check cmd sh exits 0 | `fio-check.sh --filter fail check cmd sh` | `exit 0` |
| TC-5.20 | --filter fail check cmd sh hides OK result | ↑ same run | `absent: "\[ OK \]"` |
| TC-5.21 | --filter fail check cmd <nonexistent> exits 1 | `fio-check.sh --filter fail check cmd __nonexistent_xyz_404__` | `exit 1` |
| TC-5.22 | --filter fail check cmd <nonexistent> shows FAIL | ↑ same run | `output: "FAIL\|missing"` |
| TC-5.23 | --filter warn check cmd sh exits 0 | `fio-check.sh --filter warn check cmd sh` | `exit 0` |

## Section 6 — check kconfig

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-6.1 | --dry-run check kconfig CONFIG_NET exits 0 | `fio-check.sh --dry-run check kconfig CONFIG_NET` | `exit 0` |
| TC-6.2 | --dry-run check kconfig CONFIG_NET output shows DRY | ↑ same run | `output: "DRY"` |
| TC-6.3 | --dry-run check kconfig CONFIG_INET exits 0 | `fio-check.sh --dry-run check kconfig CONFIG_INET` | `exit 0` |
| TC-6.4 | bare symbol INET (no CONFIG_ prefix) exits 0 | `fio-check.sh --dry-run check kconfig INET` | `exit 0` |
| TC-6.5 | bare symbol INET output shows DRY (prefix was stripped correctly) | ↑ same run | `output: "DRY"` |
| TC-6.6 | live check kconfig CONFIG_NET exits 0 | `fio-check.sh check kconfig CONFIG_NET` | `exit 0` |
| TC-6.7 | live check kconfig output shows a recognisable result | ↑ same run | `output: "kconfig:\|no kernel config"` |
| TC-6.8 | --dry-run check kconfig with explicit expected value exits 0 | `fio-check.sh --dry-run check kconfig CONFIG_NET y` | `exit 0` |
| TC-6.9 | --dry-run check kconfig with explicit expected value shows DRY | ↑ same run | `output: "DRY"` |

## Section 7 — check lib

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-7.1 | --dry-run check lib ssl exits 0 | `fio-check.sh --dry-run check lib ssl` | `exit 0` |
| TC-7.2 | --dry-run check lib ssl output shows DRY | ↑ same run | `output: "DRY"` |
| TC-7.3 | check lib <nonexistent lib> exits 1 | `fio-check.sh check lib __no_such_lib_xyz_404__` | `exit 1` |
| TC-7.4 | check lib <nonexistent lib> output shows NOT FOUND or FAIL | ↑ same run | `output: "NOT FOUND\|FAIL"` |
| TC-7.5 | --dry-run check lib with multiple libraries exits 0 | `fio-check.sh --dry-run check lib ssl crypto` | `exit 0` |

## Section 8 — run <lib>

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-8.1 | run <lib> without an _all function exits 0 | `fio-check.sh --lib-dir "${LIBFX}" run probe` | `exit 0` |
| TC-8.2 | run <lib> without _all warns about the missing function | ↑ same run | `output: "Function not found: lib_probe_all"` |
| TC-8.3 | run output shows Results section | ↑ same run | `output: "Results"` |
| TC-8.4 | run <lib>:<function> exits 0 | `fio-check.sh --lib-dir "${LIBFX}" run probe:ok` | `exit 0` |
| TC-8.5 | run <nonexistent file> exits 1 | `fio-check.sh run __no_such_lib__.sh` | `exit 1` |
| TC-8.6 | run <nonexistent file> output shows error message | ↑ same run | `output: "Not a profile or lib"` |
| TC-8.7 | run accepts a component name (docker -> lib_docker_all) | `fio-check.sh --dry-run run docker` | `output: "lib_docker_all"` |
| TC-8.8 | run accepts a lib file name | `fio-check.sh --dry-run run lib_docker.sh` | `exit 0` |
| TC-8.9 | run accepts components/<lib> | `fio-check.sh --dry-run run components/lib_docker.sh` | `exit 0` |
| TC-8.10 | run <lib>:<function> calls lib_<lib>_<function> | `fio-check.sh --dry-run run docker:daemon_config` | `output: "lib_docker_daemon_config"` |
| TC-8.11 | run <lib>:lib_<full name> calls that function | `fio-check.sh --dry-run run docker:lib_docker_version` | `output: "lib_docker_version"` |
| TC-8.12 | options are accepted after the command | `fio-check.sh run docker:cmds --dry-run --no-color` | `output: "DRY"` |
| TC-8.13 | run with no target exits 2 | `fio-check.sh run` | `exit 2` |
| TC-8.14 | run with two targets exits 2 | `fio-check.sh run docker fioconfig` | `exit 2` |
| TC-8.15 | run <lib>:<function> --expect <layer>/<set> loads the set | `fio-check.sh --dry-run run docker:daemon_config --expect meta-foundries/wrynose` | `output: "expect/wrynose.sh"` |
| TC-8.16 | a bare --expect name found in several layers is rejected for a lib | `fio-check.sh -r "${WORK_DIR}/run_lib_report.txt" --dry-run run lib_fioconfig.sh` | `output: "exists in several layers"` |
| TC-8.17 | -r creates a report file after run | ↑ same run | `file: "${WORK_DIR}/run_lib_report.txt"` |
| TC-8.18 | -r report file contains the Foundries header | ↑ same run | `file-has: "${WORK_DIR}/run_lib_report.txt" "Foundries Check Report"` |
| TC-8.19 | -r report file contains the PASS/FAIL/WARN/SKIP line | ↑ same run | `file-has: "${WORK_DIR}/run_lib_report.txt" "PASS: .*WARN: "` |
| TC-8.20 | --dry-run run ${name} exits 0 *(for each `lib`)* | `fio-check.sh --dry-run run "${name}"` | `exit 0` |
| TC-8.21 | --dry-run run ${name} lists checks and logs no result *(for each `lib`)* | ↑ same run | dry-run only |
| TC-8.22 | run ${name} raises no shell error *(for each `lib`)* | `fio-check.sh run "${name}"` | no shell error |

## Section 9 — run <profile>

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-9.1 | run <fixture> exits 0 | `fio-check.sh --profiles-dir "${PROFX}" run demo/demo.sh` | `exit 0` |
| TC-9.2 | run output identifies the profile | ↑ same run | `output: "Loading Profile: demo"` |
| TC-9.3 | run calls fiocheck_pre_hook | ↑ same run | `output: "pre_hook: demo"` |
| TC-9.4 | run calls fiocheck_post_hook | ↑ same run | `output: "post_hook: demo"` |
| TC-9.5 | run tags results with fiocheck_req | ↑ same run | `output: "\\[DEMO-1\\] Command exists: sh"` |
| TC-9.6 | an expectation set overrides the profile default | `fio-check.sh --profiles-dir "${PROFX}" --expect broken run demo/demo.sh` | `exit 1` |
| TC-9.7 | run <folder name> resolves the profile | `fio-check.sh --profiles-dir "${PROFX}" run demo` | `exit 0` |
| TC-9.8 | run <layer>/<name> without .sh resolves the profile | `fio-check.sh --dry-run run meta-foundries/os-update` | `exit 0` |
| TC-9.9 | run <nonexistent profile> exits 1 | `fio-check.sh run __no_such_profile_xyz__` | `exit 1` |
| TC-9.10 | run <nonexistent profile> output shows error message | `fio-check.sh -r "${WORK_DIR}/load_report.txt" --profiles-dir "${PROFX}" run demo` | `output: "Not a profile or lib"` |
| TC-9.11 | -r run report file contains the Foundries header | ↑ same run | `file-has: "${WORK_DIR}/load_report.txt" "Foundries Check Report"` |
| TC-9.12 | -r run report file records the mode | ↑ same run | `file-has: "${WORK_DIR}/load_report.txt" "Mode      : dev"` |
| TC-9.13 | -r run report file carries the requirement tag | ↑ same run | `file-has: "${WORK_DIR}/load_report.txt" "DEMO-1"` |
| TC-9.14 | --dry-run run ${p} exits 0 *(for each `p`)* | `fio-check.sh --dry-run run "${p}"` | `exit 0` |
| TC-9.15 | --dry-run run ${p} lists checks and logs no result *(for each `p`)* | ↑ same run | dry-run only |
| TC-9.16 | --expect <unknown> exits 1 | `fio-check.sh --expect __nope__ run meta-foundries/os-update` | `exit 1` |
| TC-9.17 | --expect <unknown> lists the layer's sets | ↑ same run | `output: "Available: meta-foundries/blacksail meta-foundries/wrynose"` |
| TC-9.18 | --machine <unknown> exits 1 | `fio-check.sh --machine __nope__ run meta-foundries/os-update` | `exit 1` |
| TC-9.19 | --expect <name> is reported in the run header | `fio-check.sh --dry-run --expect blacksail run meta-foundries/os-update` | `output: "Expect: blacksail"` |

## Section 10 — Static profiles (--root)

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-10.1 | fixture rootfs were generated | `make-rootfs.sh` for foundries-os, foundries-full, lmp, and foundries-full in production mode | rootfs trees and `.kconfig` files exist |
| TC-10.2 | os-update passes on an OS Update rootfs | `srun os blacksail meta-foundries/os-update --machine qemux86-64` | `exit 0` |
| TC-10.3 | os-update tags results with requirement IDs | ↑ same run | `output: "\[FR-08\]"` |
| TC-10.4 | --root mode skips runtime checks | ↑ same run | `output: "needs a running system"` |
| TC-10.5 | full-update passes on a Full Update rootfs | `srun full blacksail meta-foundries/full-update --machine qemux86-64` | `exit 0` |
| TC-10.6 | full-update checks the daemon.json entries from the expectation set | ↑ same run | `output: "max-concurrent-downloads=3"` |
| TC-10.7 | os-update fails on a Full Update rootfs (FR-01) | `srun full blacksail meta-foundries/os-update` | `exit 1` |
| TC-10.8 | os-update reports the container stack as FR-01 | ↑ same run | `output: "\[FR-01\] Command must be absent: docker"` |
| TC-10.9 | meta-lmp/lmp passes on an LmP rootfs (expect wrynose) | `srun lmp wrynose meta-lmp/lmp` | `exit 0` |
| TC-10.10 | meta-lmp/lmp passes on an LmP rootfs (expect v97) | `srun lmp v97 meta-lmp/lmp` | `exit 0` |
| TC-10.11 | a machine file sets the hardware id: mismatch fails | `srun os blacksail meta-foundries/os-update --machine uno-q` | `exit 1` |
| TC-10.12 | hardware id mismatch names both values | ↑ same run | `output: "Hardware ID: qemux86-64 — expected uno-q"` |
| TC-10.13 | the environment overrides the machine file | `srun os blacksail meta-foundries/os-update --machine uno-q` | `exit 0` |
| TC-10.14 | a substitute SOTA_CLIENT is checked through the variable (FR-06) | `srun os blacksail meta-foundries/os-update` | `output: "Command missing: custom-sota-client"` |
| TC-10.15 | the legacy lmp-device-register name fails on meta-foundries (D-18) | `srun legacy blacksail meta-foundries/os-update` | `output: "Command must be absent: lmp-device-register"` |
| TC-10.16 | /var/sota with the wrong mode fails | `srun mode blacksail meta-foundries/os-update` | `output: "Mode: /var/sota = 755 — expected 700"` |
| TC-10.17 | a disabled unit fails where enabled is required | `srun disabled blacksail meta-foundries/os-update` | `output: "unit: fioconfig.service enable=disabled — expected enabled"` |
| TC-10.18 | a masked unit fails | `srun masked blacksail meta-foundries/os-update` | `output: "unit: aktualizr-lite.service is masked"` |
| TC-10.19 | a static unit is reported as static | ↑ same run | `output: "unit: ostree-remount.service enable=static"` |
| TC-10.20 | daemon.json drift fails | `srun drift blacksail meta-foundries/full-update` | `output: "expected storage-driver=overlay2"` |
| TC-10.21 | a disabled kernel option fails | `fio-check.sh --no-color --root "${FX}/full" --kconfig "${FX}/novet.kconfig" --expect blacksail run meta-foundries/full-update` | `output: "kconfig: CONFIG_VETH is not enabled"` |
| TC-10.22 | a missing kernel config is a warning, not a pass | `fio-check.sh --no-color --root "${FX}/full" --expect blacksail run meta-foundries/full-update` | `output: "no kernel config found"` |
| TC-10.23 | a missing kernel config fails with --warn-as-fail | `fio-check.sh --no-color --warn-as-fail --root "${FX}/full" --expect blacksail run meta-foundries/full-update` | `exit 1` |
| TC-10.24 | --mode production fails on a development rootfs (SR-13) | `srun full blacksail meta-foundries/full-update --mode production` | `output: "\[SR-13\] Credentials: development user"` |
| TC-10.25 | --mode production passes on a production rootfs | `srun prod blacksail meta-foundries/full-update --mode production` | `exit 0` |
| TC-10.26 | --root <nonexistent> exits 2 | `fio-check.sh --root "${WORK_DIR}/__none__" run meta-foundries/os-update` | `exit 2` |
| TC-10.27 | --mode <invalid> exits 2 | `fio-check.sh --mode staging run meta-foundries/os-update` | `exit 2` |

## Section 11 — Core checks

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-11.1 | check_cmd_version passes a satisfied minimum | `crun lib_core_ver_ok` | `exit 0` |
| TC-11.2 | check_cmd_version fails a version below the minimum | `crun lib_core_ver_old` | `exit 1` |
| TC-11.3 | check_cmd_version compares segments numerically (29.7 < 29.10) | `crun lib_core_ver_minor` | `exit 1` |
| TC-11.4 | check_cmd_version raises no shell error | ↑ same run | no shell error |
| TC-11.5 | check_cmd_version matches an exact commit | `crun lib_core_ver_exact` | `exit 0` |
| TC-11.6 | check_cmd_version without expectation reports only | `crun lib_core_ver_report` | `output: "29.7.2 (not enforced)"` |
| TC-11.7 | check_cmd_version on a missing command fails cleanly | `crun lib_core_ver_missing` | `output: "command missing"` |
| TC-11.8 | check_cmd_version on a missing command raises no shell error | ↑ same run | no shell error |
| TC-11.9 | _compare_versions orders versions | `crun lib_core_cmp` | `exit 0` |
| TC-11.10 | check_lib_dependency fails a missing library | `crun lib_core_lib_missing` | `exit 1` |
| TC-11.11 | check_lib_dependency accepts names with and without lib prefix (--root) | `crun lib_core_lib_prefix --root "${FX}/os"` | `exit 0` |
| TC-11.12 | --dry-run check_sysctl does not run sysctl | `crun lib_core_sysctl_dry --dry-run` | dry-run only |

## Section 12 — Search paths and standalone use

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-12.1 | standalone: help exits 0 | `arun --no-color help` | `exit 0` |
| TC-12.2 | standalone: list exits 0 | `arun --no-color list` | `exit 0` |
| TC-12.3 | standalone: list reports the empty search paths | ↑ same run | `output: "No lib directory"` |
| TC-12.4 | standalone: check cmd works without libs | `arun --no-color check cmd sh` | `exit 0` |
| TC-12.5 | standalone: run <lib> fails and names the search paths | `arun --no-color run docker` | `output: "Searched libs in: *nothing"` |
| TC-12.6 | standalone: run <lib> exits 1 | ↑ same run | `exit 1` |
| TC-12.7 | standalone: run <profile file> reports a missing lib as FAIL | `arun --no-color run "${EXT}/profiles/product/smoke.sh"` | `output: "Lib not found: probe"` |
| TC-12.8 | standalone: run <profile file> with a missing lib exits 1 | ↑ same run | `exit 1` |
| TC-12.9 | standalone: --lib-dir supplies the libs a profile file needs | `arun --no-color --lib-dir "${LIBFX}" run "${EXT}/profiles/product/smoke.sh"` | `exit 0` |
| TC-12.10 | --no-builtin ignores lib/ next to fio-check.sh | `fio-check.sh --no-color --no-builtin run docker` | `exit 1` |
| TC-12.11 | --profiles-dir adds a profile directory; built-in libs stay available | `fio-check.sh --no-color --profiles-dir "${EXT}/profiles" --lib-dir "${LIBFX}" run product/smoke` | `exit 0` |
| TC-12.12 | a profile from an added directory tags its results | ↑ same run | `output: "\[PROD-1\] Command exists: sh"` |
| TC-12.13 | built-in profiles are still found with an added profile directory | `fio-check.sh --no-color --dry-run --profiles-dir "${EXT}/profiles" run meta-foundries/os-update` | `exit 0` |
| TC-12.14 | FIOCHECK_PROFILE_PATH and FIOCHECK_LIB_PATH add directories | `fio-check.sh --no-color run product/smoke` | `exit 0` |
| TC-12.15 | an expectation set in an added profile directory is found | `fio-check.sh --no-color --profiles-dir "${EXT}/profiles" --lib-dir "${LIBFX}" --expect broken run product/smoke` | `output: "Command missing: __no_such_cmd__"` |
| TC-12.16 | an added lib directory overrides a built-in lib | `fio-check.sh --no-color --lib-dir "${EXT}/lib" run docker:cmds` | `output: "overridden lib_docker_cmds"` |
| TC-12.17 | the first --lib-dir wins | `fio-check.sh --no-color --lib-dir "${EXT}/lib2" --lib-dir "${EXT}/lib" run docker:cmds` | `output: "second lib_docker_cmds"` |
| TC-12.18 | list marks a lib hidden by an earlier directory | `fio-check.sh --no-color --lib-dir "${EXT}/lib" list` | `output: "overridden earlier in the path"` |
| TC-12.19 | list shows the search paths | ↑ same run | `output: "Lib search path: *${EXT}/lib:"` |
| TC-12.20 | a missing --lib-dir is reported and ignored | `fio-check.sh --no-color --lib-dir "${WORK_DIR}/__none__" check cmd sh` | `output: "not a directory"` |
| TC-12.21 | a missing --lib-dir does not fail the run | ↑ same run | `exit 0` |

## Section 13 — Portability lint

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-13.1 | no legacy head/tail -N (OE busybox rejects it) | `grep -rnE '(head\|tail) -[0-9]' <shell sources>` | no match outside comments |
| TC-13.2 | no cat -v (not in OE busybox) | `grep -rnE 'cat -v' <shell sources>` | no match outside comments |
| TC-13.3 | no bash [[ ]] tests | `grep -rnE '\[\[ ' <shell sources>` | no match outside comments |
| TC-13.4 | no bash 'source' builtin | `grep -rnE '(^\|[;&\|[:space:]])source [^-]' <shell sources>` | no match outside comments |
| TC-13.5 | no 'function' keyword | `grep -rnE '^[[:space:]]*function [a-z_]' <shell sources>` | no match outside comments |
| TC-13.6 | no undefined _dry_print helper | `grep -rnE '_dry_print' <shell sources>` | no match outside comments |
| TC-13.7 | no GNU-only sed -i / grep -P / sort -V | `grep -rnE 'sed -i\|grep -[a-zA-Z]*P\|sort -V' <shell sources>` | no match outside comments |

## Section 14 — Missing / invalid arguments

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-14.1 | --report with no filename exits non-0 | `fio-check.sh --report` | `exit 2` |
| TC-14.2 | --filter with no value exits non-0 | `fio-check.sh --filter` | `exit 2` |
| TC-14.3 | the removed --fn option is rejected | `fio-check.sh --fn x run docker` | `exit 1` |
| TC-14.4 | --profiles-dir with no path exits non-0 | `fio-check.sh --profiles-dir` | `exit 2` |
| TC-14.5 | --lib-dir with no path exits non-0 | `fio-check.sh --lib-dir` | `exit 2` |
| TC-14.6 | run with no lib path exits non-0 | `fio-check.sh run` | `exit 2` |
| TC-14.7 | run with no profile path exits non-0 | `fio-check.sh run` | `exit 2` |

## Section 15 — Option combinations

| ID | Test case | Command | Expected |
|---|---|---|---|
| TC-15.1 | --no-color --verbose check cmd sh exits 0 | `fio-check.sh --no-color --verbose check cmd sh` | `exit 0` |
| TC-15.2 | --no-color --verbose output has no ANSI sequences | ↑ same run | no ANSI escapes |
| TC-15.3 | --no-color --verbose output still shows VERB lines | ↑ same run | `output: "VERB"` |
| TC-15.4 | --quiet --filter fail on missing command exits 1 | `fio-check.sh --quiet --filter fail check cmd __nonexistent_xyz_404__` | `exit 1` |
| TC-15.5 | --dry-run --verbose check kconfig exits 0 | `fio-check.sh --dry-run --verbose check kconfig CONFIG_NET` | `exit 0` |
| TC-15.6 | --dry-run --verbose output shows DRY marker | ↑ same run | `output: "DRY"` |
| TC-15.7 | --dry-run --no-color list exits 0 | `fio-check.sh --dry-run --no-color list` | `exit 0` |
| TC-15.8 | --dry-run --no-color output has no ANSI sequences | ↑ same run | no ANSI escapes |
| TC-15.9 | --filter fail,warn check cmd sh exits 0 | `fio-check.sh --filter "fail,warn" check cmd sh` | `exit 0` |
| TC-15.10 | --filter fail,warn hides OK results | ↑ same run | `absent: "\[ OK \]"` |
| TC-15.11 | --filter fail,ok check cmd sh exits 0 | `fio-check.sh --filter "fail,ok" check cmd sh` | `exit 0` |
| TC-15.12 | --filter fail,ok shows OK results | ↑ same run | `output: "OK"` |
| TC-15.13 | -v is a short alias for --verbose | `fio-check.sh -v check cmd sh` | `exit 0` |
| TC-15.14 | -v output shows VERB lines | ↑ same run | `output: "VERB"` |
| TC-15.15 | -q is a short alias for --quiet | `fio-check.sh -q check cmd sh` | `exit 0` |
| TC-15.16 | -q suppresses OK output | ↑ same run | `absent: "\[ OK \]"` |
| TC-15.17 | -r is a short alias for --report | `fio-check.sh -r "${WORK_DIR}/short_alias_report.txt" --dry-run run lib_fioconfig.sh` | `exit 0` |
| TC-15.18 | -r creates the report file | ↑ same run | `file: "${WORK_DIR}/short_alias_report.txt"` |
## Section P — Profile matrix (tests/validate-profiles.sh)

Every profile is checked against every expectation set and machine of its
layer. Each combination is its own fio-check process, run against a fresh
fixture rootfs (the profile's `# Fixture :` header) with `--root`, and writes
its own report. A failure prints the command that reproduces it alone. New
expectation sets (e.g. `profiles/meta-lmp/expect/v98.sh`), machines and
profiles join the matrix automatically; `--profiles-dir <dir>` adds the
layers of another profile tree.

**Expected:** every combination exits `0`.

| ID | Profile | Expectation set | Machine |
|---|---|---|---|
| TC-P.1 | meta-foundries/full-update | blacksail | qemuarm64-secureboot |
| TC-P.2 | meta-foundries/full-update | blacksail | qemux86-64 |
| TC-P.3 | meta-foundries/full-update | blacksail | uno-q |
| TC-P.4 | meta-foundries/full-update | wrynose | qemuarm64-secureboot |
| TC-P.5 | meta-foundries/full-update | wrynose | qemux86-64 |
| TC-P.6 | meta-foundries/full-update | wrynose | uno-q |
| TC-P.7 | meta-foundries/os-update | blacksail | qemuarm64-secureboot |
| TC-P.8 | meta-foundries/os-update | blacksail | qemux86-64 |
| TC-P.9 | meta-foundries/os-update | blacksail | uno-q |
| TC-P.10 | meta-foundries/os-update | wrynose | qemuarm64-secureboot |
| TC-P.11 | meta-foundries/os-update | wrynose | qemux86-64 |
| TC-P.12 | meta-foundries/os-update | wrynose | uno-q |
| TC-P.13 | meta-lmp/lmp | v97 | — |
| TC-P.14 | meta-lmp/lmp | wrynose | — |
