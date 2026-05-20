# Test Plan — fio-check.sh

| | |
|---|---|
| **Document** | test_plan.md |
| **Script** | test_fio_check.sh |
| **Tool under test** | fio-check.sh v0.0.1 |
| **Date** | 2026-05-18 |
| **Total test cases** | 144 |

---

## Overview

### Purpose

Verify that every CLI command, option, option combination, and error path of `fio-check.sh` behaves as documented. The plan has a 1-to-1 mapping with `test_fio_check.sh` so failures can be traced directly to individual test cases.

### How to Run

```sh
cd /path/to/fio-check
./test_fio_check.sh      # normal
./test_fio_check.sh -v   # verbose — shows captured output on failure
```

Exit code `0` = all tests passed, `1` = one or more failed.

### Notation

| Token | Meaning |
|---|---|
| `exit N` | Script must exit with code N |
| `exit 0\|1` | Script may exit with either code (system-dependent) |
| `output: <text>` | Combined stdout+stderr must contain the string |
| `absent: <text>` | Combined stdout+stderr must NOT contain the string |
| `file: <path>` | File must exist on disk |
| `file-has: <text>` | File content must contain the string |

### Bug B2 — fixed

> Bug B2 (`--dry-run` not propagated to lib scripts) has been corrected.
> `fio-check.sh` now exports `FIOCHECK_DRY_RUN=1` when `--dry-run` is given,
> and all lib scripts have been updated to check that variable.
> Tests in sections 9–11 now assert exit `0` for dry-run invocations.

---

## Section 1 — Preconditions

Verify the script is present and executable before any other test runs. If either of these fails all subsequent tests are meaningless.

### TC-1.1 — Script file exists

**Check:** `[ -f ./fio-check.sh ]`  
**Expected:** file exists

### TC-1.2 — Script is executable

**Check:** `[ -x ./fio-check.sh ]`  
**Expected:** executable bit set

---

## Section 2 — Help / Usage

Verify that every form of requesting help prints usage information and that invalid input is rejected.

### TC-2.1 — `help` command — exit code

**Command:** `./fio-check.sh help`  
**Expected:** exit `0`

### TC-2.2 — `help` command — USAGE section present

**Command:** `./fio-check.sh help`  
**Expected:** output: `USAGE`

### TC-2.3 — `help` command — COMMANDS section present

**Command:** `./fio-check.sh help`  
**Expected:** output: `COMMANDS`

### TC-2.4 — `help` command — OPTIONS section present

**Command:** `./fio-check.sh help`  
**Expected:** output: `OPTIONS`

### TC-2.5 — `--help` long flag — exit code

**Command:** `./fio-check.sh --help`  
**Expected:** exit `0`

### TC-2.6 — `--help` long flag — tool name present

**Command:** `./fio-check.sh --help`  
**Expected:** output: `fio-check`

### TC-2.7 — `-h` short flag — exit code

**Command:** `./fio-check.sh -h`  
**Expected:** exit `0`

### TC-2.8 — No arguments — shows usage

**Command:** `./fio-check.sh`  
**Expected:** exit `0`

### TC-2.9 — No arguments — USAGE string present

**Command:** `./fio-check.sh`  
**Expected:** output: `USAGE`

### TC-2.10 — Unknown command — rejected

**Command:** `./fio-check.sh bad-command`  
**Expected:** exit `1`

### TC-2.11 — Unknown command — error message

**Command:** `./fio-check.sh bad-command`  
**Expected:** output: `Unknown`

### TC-2.12 — Unknown option — rejected

**Command:** `./fio-check.sh --bad-flag`  
**Expected:** exit `1`

---

## Section 3 — list-libs

Verify that `list-libs` enumerates lib modules, respects `--lib-dir`, and is unaffected by display options.

### TC-3.1 — Basic invocation — exit code

**Command:** `./fio-check.sh list-libs`  
**Expected:** exit `0`

### TC-3.2 — Basic invocation — Docker lib visible

**Command:** `./fio-check.sh list-libs`  
**Expected:** output: `lib_docker`

### TC-3.3 — Basic invocation — foundries group visible

**Command:** `./fio-check.sh list-libs`  
**Expected:** output: `foundries`

### TC-3.4 — With `--verbose` — exit code

**Command:** `./fio-check.sh --verbose list-libs`  
**Expected:** exit `0`  
**Note:** `list-libs` does not call `check_*` functions so no `VERB` lines are expected; the flag must not cause a crash.

### TC-3.5 — With `--quiet` — exit code

**Command:** `./fio-check.sh --quiet list-libs`  
**Expected:** exit `0`

### TC-3.6 — With `--no-color` — exit code

**Command:** `./fio-check.sh --no-color list-libs`  
**Expected:** exit `0`

### TC-3.7 — With `--no-color` — no ANSI escape sequences

**Command:** `./fio-check.sh --no-color list-libs`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

### TC-3.8 — `--lib-dir` pointing to valid lib directory

**Command:** `./fio-check.sh --lib-dir ./lib list-libs`  
**Expected:** exit `0`; output: `lib_docker`

### TC-3.9 — `--lib-dir` pointing to valid directory — lib visible

**Command:** `./fio-check.sh --lib-dir ./lib list-libs`  
**Expected:** output: `lib_docker`

### TC-3.10 — `--lib-dir` pointing to empty directory

**Command:** `./fio-check.sh --lib-dir <empty_tmpdir> list-libs`  
**Expected:** exit `0`; output: `No lib modules` or `not found`

### TC-3.11 — `--lib-dir` pointing to empty directory — warning shown

**Command:** `./fio-check.sh --lib-dir <empty_tmpdir> list-libs`  
**Expected:** output: `No lib modules` or `not found`

### TC-3.12 — `--lib-dir` pointing to nonexistent directory

**Command:** `./fio-check.sh --lib-dir /no_such_dir_xyz list-libs`  
**Expected:** exit `0`

---

## Section 4 — list-profiles

Verify that `list-profiles` enumerates available profiles and respects `--profiles-dir`.

### TC-4.1 — Basic invocation — exit code

**Command:** `./fio-check.sh list-profiles`  
**Expected:** exit `0`

### TC-4.2 — Basic invocation — at least one profile visible

**Command:** `./fio-check.sh list-profiles`  
**Expected:** output: `docker` or `foundries`

### TC-4.3 — `--profiles-dir` with valid directory — exit code

**Command:** `./fio-check.sh --profiles-dir ./profiles list-profiles`  
**Expected:** exit `0`

### TC-4.4 — `--profiles-dir` with valid directory — profiles visible

**Command:** `./fio-check.sh --profiles-dir ./profiles list-profiles`  
**Expected:** output: `docker`

### TC-4.5 — `--profiles-dir` pointing to empty directory

**Command:** `./fio-check.sh --profiles-dir <empty_tmpdir> list-profiles`  
**Expected:** exit `0`; output: `No profiles` or `not found`

### TC-4.6 — `--profiles-dir` pointing to empty directory — warning shown

**Command:** `./fio-check.sh --profiles-dir <empty_tmpdir> list-profiles`  
**Expected:** output: `No profiles` or `not found`

### TC-4.7 — With `--no-color` — exit code

**Command:** `./fio-check.sh --no-color list-profiles`  
**Expected:** exit `0`

### TC-4.8 — With `--no-color` — no ANSI escape sequences

**Command:** `./fio-check.sh --no-color list-profiles`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

---

## Section 5 — check-cmd

Verify the command existence checker under all display options and with both passing and failing inputs.

### TC-5.1 — Known-present command — exit code

**Command:** `./fio-check.sh check-cmd sh`  
**Expected:** exit `0`  
**Note:** `sh` is always present on the test host.

### TC-5.2 — Known-present command — OK in output

**Command:** `./fio-check.sh check-cmd sh`  
**Expected:** output: `OK`

### TC-5.3 — Multiple present commands — all pass

**Command:** `./fio-check.sh check-cmd sh ls cat`  
**Expected:** exit `0`

### TC-5.4 — Nonexistent command — exit code

**Command:** `./fio-check.sh check-cmd __nonexistent_xyz_404__`  
**Expected:** exit `1`

### TC-5.5 — Nonexistent command — FAIL in output

**Command:** `./fio-check.sh check-cmd __nonexistent_xyz_404__`  
**Expected:** output: `FAIL` or `missing`

### TC-5.6 — Mixed present/missing commands — exit code

**Command:** `./fio-check.sh check-cmd sh __nonexistent_xyz_404__`  
**Expected:** exit `1`

### TC-5.7 — `--dry-run` — exit code

**Command:** `./fio-check.sh --dry-run check-cmd sh`  
**Expected:** exit `0`

### TC-5.8 — `--dry-run` — DRY marker in output

**Command:** `./fio-check.sh --dry-run check-cmd sh`  
**Expected:** output: `DRY`

### TC-5.9 — `--dry-run` — check not actually executed

**Command:** `./fio-check.sh --dry-run check-cmd sh`  
**Expected:** absent: `[ OK ]`  
**Note:** Dry-run must not log a pass result, only announce intent.

### TC-5.10 — `--verbose` — exit code

**Command:** `./fio-check.sh --verbose check-cmd sh`  
**Expected:** exit `0`

### TC-5.11 — `--verbose` — VERB lines in output

**Command:** `./fio-check.sh --verbose check-cmd sh`  
**Expected:** output: `VERB`

### TC-5.12 — `--quiet` — exit code

**Command:** `./fio-check.sh --quiet check-cmd sh`  
**Expected:** exit `0`

### TC-5.13 — `--quiet` — OK result suppressed

**Command:** `./fio-check.sh --quiet check-cmd sh`  
**Expected:** absent: `[ OK ]`

### TC-5.14 — `--no-color` — exit code

**Command:** `./fio-check.sh --no-color check-cmd sh`  
**Expected:** exit `0`

### TC-5.15 — `--no-color` — no ANSI escape sequences

**Command:** `./fio-check.sh --no-color check-cmd sh`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

### TC-5.16 — `--no-color` — plain OK text still present

**Command:** `./fio-check.sh --no-color check-cmd sh`  
**Expected:** output: `OK`

### TC-5.17 — `--filter ok` — exit code

**Command:** `./fio-check.sh --filter ok check-cmd sh`  
**Expected:** exit `0`

### TC-5.18 — `--filter ok` — OK result shown

**Command:** `./fio-check.sh --filter ok check-cmd sh`  
**Expected:** output: `OK`

### TC-5.19 — `--filter fail` on passing check — exit code

**Command:** `./fio-check.sh --filter fail check-cmd sh`  
**Expected:** exit `0`

### TC-5.20 — `--filter fail` on passing check — OK suppressed

**Command:** `./fio-check.sh --filter fail check-cmd sh`  
**Expected:** absent: `[ OK ]`

### TC-5.21 — `--filter fail` on failing check — exit code

**Command:** `./fio-check.sh --filter fail check-cmd __nonexistent_xyz_404__`  
**Expected:** exit `1`

### TC-5.22 — `--filter fail` on failing check — FAIL shown

**Command:** `./fio-check.sh --filter fail check-cmd __nonexistent_xyz_404__`  
**Expected:** output: `FAIL` or `missing`

### TC-5.23 — `--filter warn` on passing check

**Command:** `./fio-check.sh --filter warn check-cmd sh`  
**Expected:** exit `0`

---

## Section 6 — check-kconfig

Verify kernel config symbol lookup, `CONFIG_` prefix stripping, optional expected-value argument, and dry-run behaviour. Live checks are system-dependent and may skip if no kernel config is found.

### TC-6.1 — `--dry-run` with `CONFIG_` prefix — exit code

**Command:** `./fio-check.sh --dry-run check-kconfig CONFIG_NET`  
**Expected:** exit `0`

### TC-6.2 — `--dry-run` with `CONFIG_` prefix — DRY in output

**Command:** `./fio-check.sh --dry-run check-kconfig CONFIG_NET`  
**Expected:** output: `DRY`

### TC-6.3 — `--dry-run` verifies `CONFIG_` prefix is accepted

**Command:** `./fio-check.sh --dry-run check-kconfig CONFIG_INET`  
**Expected:** exit `0`

### TC-6.4 — Bare symbol (no `CONFIG_` prefix) — stripped correctly

**Command:** `./fio-check.sh --dry-run check-kconfig INET`  
**Expected:** exit `0`

### TC-6.5 — Bare symbol — DRY output confirms symbol used

**Command:** `./fio-check.sh --dry-run check-kconfig INET`  
**Expected:** output: `DRY`

### TC-6.6 — Live check — does not crash ⚠️

**Command:** `./fio-check.sh check-kconfig CONFIG_NET`  
**Expected:** exit `0|1` — depends on whether kernel config is accessible

### TC-6.7 — Live check — produces recognisable output ⚠️

**Command:** `./fio-check.sh check-kconfig CONFIG_NET`  
**Expected:** output: `kconfig:` or `no kernel config`

### TC-6.8 — With explicit expected value — dry-run exit code

**Command:** `./fio-check.sh --dry-run check-kconfig CONFIG_NET y`  
**Expected:** exit `0`

### TC-6.9 — With explicit expected value — DRY output

**Command:** `./fio-check.sh --dry-run check-kconfig CONFIG_NET y`  
**Expected:** output: `DRY`

---

## Section 7 — check-deps

Verify shared-library dependency checking: dry-run, failure output, and multi-library invocation.

### TC-7.1 — `--dry-run` single library — exit code

**Command:** `./fio-check.sh --dry-run check-deps ssl`  
**Expected:** exit `0`

### TC-7.2 — `--dry-run` single library — DRY in output

**Command:** `./fio-check.sh --dry-run check-deps ssl`  
**Expected:** output: `DRY`

### TC-7.3 — Nonexistent library — exit code

**Command:** `./fio-check.sh check-deps __no_such_lib_xyz_404__`  
**Expected:** exit `1`

### TC-7.4 — Nonexistent library — FAIL in output

**Command:** `./fio-check.sh check-deps __no_such_lib_xyz_404__`  
**Expected:** output: `NOT FOUND` or `FAIL`

### TC-7.5 — Multiple libraries with `--dry-run`

**Command:** `./fio-check.sh --dry-run check-deps ssl crypto`  
**Expected:** exit `0`

---

## Section 8 — run-lib

Verify that `run-lib` sources a lib file, calls the derived `_all` function or an explicit `--fn` override, produces a Results section, generates a report with `-r`, and handles missing inputs correctly.

### TC-8.1 — Lib with no `_all` function — exit code

**Command:** `./fio-check.sh run-lib foundries/lib_aktualizr.sh`  
**Expected:** exit `0`  
**Note:** `lib_aktualizr.sh` defines no `lib_aktualizr_all` function. `run_lib` logs a warning but exits `0` because no check logged a FAIL.

### TC-8.2 — Lib with no `_all` function — warning shown

**Command:** `./fio-check.sh run-lib foundries/lib_aktualizr.sh`  
**Expected:** output: `not found` or `WARN`

### TC-8.3 — Lib with no `_all` function — Results section present

**Command:** `./fio-check.sh run-lib foundries/lib_aktualizr.sh`  
**Expected:** output: `Results`

### TC-8.4 — Nonexistent lib file — exit code

**Command:** `./fio-check.sh run-lib __no_such_lib__.sh`  
**Expected:** exit `1`

### TC-8.5 — Nonexistent lib file — error message

**Command:** `./fio-check.sh run-lib __no_such_lib__.sh`  
**Expected:** output: `not found` or `Lib not found`

### TC-8.6 — `--dry-run` — exit code

**Command:** `./fio-check.sh --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** exit `0`

### TC-8.7 — `--dry-run` — DRY marker in output

**Command:** `./fio-check.sh --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** output: `DRY` or `dry`

### TC-8.8 — `--fn` with a valid function name — exit code

**Command:** `./fio-check.sh --fn lib_aktualizr_set_version run-lib foundries/lib_aktualizr.sh`  
**Expected:** exit `0`  
**Note:** `lib_aktualizr_set_version()` simply sets a variable; no checks are run so exit is always `0`.

### TC-8.9 — `--fn` with a valid function name — Results section

**Command:** `./fio-check.sh --fn lib_aktualizr_set_version run-lib foundries/lib_aktualizr.sh`  
**Expected:** output: `Results`

### TC-8.10 — `--dry-run` combined with `--fn` — exit code

**Command:** `./fio-check.sh --dry-run --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh`  
**Expected:** exit `0`

### TC-8.11 — `--dry-run` combined with `--fn` — DRY output

**Command:** `./fio-check.sh --dry-run --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh`  
**Expected:** output: `DRY`

### TC-8.12 — `--verbose` with `--fn` that calls `check_*` — exit code ⚠️

**Command:** `./fio-check.sh --verbose --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh`  
**Expected:** exit `0|1` — system-dependent: `aktualizr-lite` may not be installed

### TC-8.13 — `--verbose` with `--fn` that calls `check_*` — VERB lines present ⚠️

**Command:** `./fio-check.sh --verbose --fn lib_aktualizr_cmd run-lib foundries/lib_aktualizr.sh`  
**Expected:** output: `VERB`  
**Note:** `check_cmd()` calls `print_verbose` before the existence test so `VERB` appears regardless of whether the binary is installed.

### TC-8.14 — `--filter fail` with `--dry-run` — exit code

**Command:** `./fio-check.sh --filter fail --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** exit `0`

### TC-8.15 — `--filter fail` with `--dry-run` — OK results suppressed

**Command:** `./fio-check.sh --filter fail --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** absent: `[ OK ]`

### TC-8.16 — `--no-color` with `--dry-run` — exit code

**Command:** `./fio-check.sh --no-color --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** exit `0`

### TC-8.17 — `--no-color` with `--dry-run` — no ANSI escape sequences

**Command:** `./fio-check.sh --no-color --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

### TC-8.18 — `--lib-dir` override — exit code

**Command:** `./fio-check.sh --lib-dir ./lib --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** exit `0`

### TC-8.19 — `-r` creates a report file

**Command:** `./fio-check.sh -r <tmpdir>/rl_report.txt --dry-run --fn lib_aktualizr_set_version run-lib foundries/lib_aktualizr.sh`  
**Expected:** exit `0`; file: `<tmpdir>/rl_report.txt`

### TC-8.20 — `-r` report file — header line

**Expected:** file contains `Foundries Check Report`

### TC-8.21 — `-r` report file — PASS summary line

**Expected:** file contains `PASS:`

---

## Section 9 — run-all-libs

Verify that `run-all-libs` discovers all lib modules, prints a summary table, and accepts display options.

### TC-9.1 — `--dry-run` — exits 0

**Command:** `./fio-check.sh --dry-run run-all-libs`  
**Expected:** exit `0`

### TC-9.2 — `--dry-run` — summary table header present

**Command:** `./fio-check.sh --dry-run run-all-libs`  
**Expected:** output: `Run All Libs`

### TC-9.3 — `--dry-run` — module count shown

**Command:** `./fio-check.sh --dry-run run-all-libs`  
**Expected:** output: `module`

### TC-9.4 — `--quiet --dry-run` — exits 0

**Command:** `./fio-check.sh --quiet --dry-run run-all-libs`  
**Expected:** exit `0`

### TC-9.5 — `--filter fail --dry-run` — exits 0

**Command:** `./fio-check.sh --filter fail --dry-run run-all-libs`  
**Expected:** exit `0`

### TC-9.6 — `--no-color --dry-run` — exits 0

**Command:** `./fio-check.sh --no-color --dry-run run-all-libs`  
**Expected:** exit `0`

### TC-9.7 — `--no-color --dry-run` — no ANSI escape sequences

**Command:** `./fio-check.sh --no-color --dry-run run-all-libs`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

### TC-9.8 — `-r --dry-run` — exits 0

**Command:** `./fio-check.sh -r <tmpdir>/all_libs.txt --dry-run --fn lib_aktualizr_set_version run-all-libs`  
**Expected:** exit `0`

---

## Section 10 — run-all

Verify that `run-all` discovers all profiles, runs each one, prints a combined summary table, and accepts display and path options.

### TC-10.1 — `--dry-run` — exits 0

**Command:** `./fio-check.sh --dry-run run-all`  
**Expected:** exit `0`

### TC-10.2 — `--dry-run` — summary header present

**Command:** `./fio-check.sh --dry-run run-all`  
**Expected:** output: `Run All`

### TC-10.3 — `--dry-run` — profile count shown

**Command:** `./fio-check.sh --dry-run run-all`  
**Expected:** output: `profile`

### TC-10.4 — `--quiet --dry-run` — exits 0

**Command:** `./fio-check.sh --quiet --dry-run run-all`  
**Expected:** exit `0`

### TC-10.5 — `--filter fail --dry-run` — exits 0

**Command:** `./fio-check.sh --filter fail --dry-run run-all`  
**Expected:** exit `0`

### TC-10.6 — `--no-color --dry-run` — exits 0

**Command:** `./fio-check.sh --no-color --dry-run run-all`  
**Expected:** exit `0`

### TC-10.7 — `--no-color --dry-run` — no ANSI escape sequences

**Command:** `./fio-check.sh --no-color --dry-run run-all`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

### TC-10.8 — `--profiles-dir` override — exits 0

**Command:** `./fio-check.sh --profiles-dir ./profiles --dry-run run-all`  
**Expected:** exit `0`

---

## Section 11 — load

Verify that `load` resolves profiles by path and by folder name, generates a report with `-r`, and rejects nonexistent targets.

### TC-11.1 — `--dry-run` load by file path — exits 0

**Command:** `./fio-check.sh --dry-run load docker/docker.sh`  
**Expected:** exit `0`

### TC-11.2 — `--dry-run` load by file path — profile identified in output

**Command:** `./fio-check.sh --dry-run load docker/docker.sh`  
**Expected:** output: `docker`, `Profile`, or `Loading`

### TC-11.3 — `--dry-run` load by folder name — exits 0

**Command:** `./fio-check.sh --dry-run load docker`  
**Expected:** exit `0`  
**Note:** Folder-name resolution: finds first `.sh` inside `profiles/docker/`.

### TC-11.4 — Nonexistent profile — exit code

**Command:** `./fio-check.sh load __no_such_profile_xyz__`  
**Expected:** exit `1`

### TC-11.5 — Nonexistent profile — error message

**Command:** `./fio-check.sh load __no_such_profile_xyz__`  
**Expected:** output: `not found` or `Profile not found`

### TC-11.6 — `-r` creates a report file

**Command:** `./fio-check.sh -r <tmpdir>/load_report.txt --dry-run load docker/docker.sh`  
**Expected:** file: `<tmpdir>/load_report.txt`

### TC-11.7 — `-r` report file — header line

**Expected:** file contains `Foundries Check Report`

### TC-11.8 — `-r` report file — PASS summary line

**Expected:** file contains `PASS:`

### TC-11.9 — `--filter fail --dry-run` — exits 0

**Command:** `./fio-check.sh --filter fail --dry-run load docker/docker.sh`  
**Expected:** exit `0`

### TC-11.10 — `--no-color --dry-run` — exits 0

**Command:** `./fio-check.sh --no-color --dry-run load docker/docker.sh`  
**Expected:** exit `0`

### TC-11.11 — `--no-color --dry-run` — no ANSI escape sequences

**Command:** `./fio-check.sh --no-color --dry-run load docker/docker.sh`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

---

## Section 12 — Missing / Invalid Arguments

Verify that every option requiring a value, and every command requiring a positional argument, exits non-zero when that value or argument is absent.

### TC-12.1 — `--report` with no filename

**Command:** `./fio-check.sh --report`  
**Expected:** exit `1`

### TC-12.2 — `--filter` with no value

**Command:** `./fio-check.sh --filter`  
**Expected:** exit `1`

### TC-12.3 — `--fn` with no function name

**Command:** `./fio-check.sh --fn`  
**Expected:** exit `1`

### TC-12.4 — `--profiles-dir` with no path

**Command:** `./fio-check.sh --profiles-dir`  
**Expected:** exit `1`

### TC-12.5 — `--lib-dir` with no path

**Command:** `./fio-check.sh --lib-dir`  
**Expected:** exit `1`

### TC-12.6 — `run-lib` with no lib path

**Command:** `./fio-check.sh run-lib`  
**Expected:** exit `1`

### TC-12.7 — `load` with no profile path

**Command:** `./fio-check.sh load`  
**Expected:** exit `1`

---

## Section 13 — Option Combinations

Verify that multiple options coexist correctly and do not interfere with each other or with command behaviour.

### TC-13.1 — `--no-color` + `--verbose` together — exit code

**Command:** `./fio-check.sh --no-color --verbose check-cmd sh`  
**Expected:** exit `0`

### TC-13.2 — `--no-color` + `--verbose` — no ANSI sequences

**Command:** `./fio-check.sh --no-color --verbose check-cmd sh`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

### TC-13.3 — `--no-color` + `--verbose` — VERB lines still present

**Command:** `./fio-check.sh --no-color --verbose check-cmd sh`  
**Expected:** output: `VERB`

### TC-13.4 — `--quiet` + `--filter fail` on a failing check

**Command:** `./fio-check.sh --quiet --filter fail check-cmd __nonexistent_xyz_404__`  
**Expected:** exit `1`  
**Note:** `--quiet` suppresses non-fail output; `--filter fail` lets FAIL lines through. The command still exits `1`.

### TC-13.5 — `--dry-run` + `--verbose` — exit code

**Command:** `./fio-check.sh --dry-run --verbose check-kconfig CONFIG_NET`  
**Expected:** exit `0`

### TC-13.6 — `--dry-run` + `--verbose` — DRY marker present

**Command:** `./fio-check.sh --dry-run --verbose check-kconfig CONFIG_NET`  
**Expected:** output: `DRY`

### TC-13.7 — `--dry-run` + `--no-color` — exit code

**Command:** `./fio-check.sh --dry-run --no-color list-libs`  
**Expected:** exit `0`

### TC-13.8 — `--dry-run` + `--no-color` — no ANSI sequences

**Command:** `./fio-check.sh --dry-run --no-color list-libs`  
**Expected:** absent: ANSI CSI escape sequence (`ESC[`)

### TC-13.9 — `--filter` with comma-separated `fail,warn` — exit code

**Command:** `./fio-check.sh --filter "fail,warn" check-cmd sh`  
**Expected:** exit `0`

### TC-13.10 — `--filter fail,warn` — OK results suppressed

**Command:** `./fio-check.sh --filter "fail,warn" check-cmd sh`  
**Expected:** absent: `[ OK ]`

### TC-13.11 — `--filter fail,ok` — exit code

**Command:** `./fio-check.sh --filter "fail,ok" check-cmd sh`  
**Expected:** exit `0`

### TC-13.12 — `--filter fail,ok` — OK results visible

**Command:** `./fio-check.sh --filter "fail,ok" check-cmd sh`  
**Expected:** output: `OK`

### TC-13.13 — `-v` short alias for `--verbose` — exit code

**Command:** `./fio-check.sh -v check-cmd sh`  
**Expected:** exit `0`

### TC-13.14 — `-v` short alias — VERB lines present

**Command:** `./fio-check.sh -v check-cmd sh`  
**Expected:** output: `VERB`

### TC-13.15 — `-q` short alias for `--quiet` — exit code

**Command:** `./fio-check.sh -q check-cmd sh`  
**Expected:** exit `0`

### TC-13.16 — `-q` short alias — OK output suppressed

**Command:** `./fio-check.sh -q check-cmd sh`  
**Expected:** absent: `[ OK ]`

### TC-13.17 — `-r` short alias for `--report` — exit code

**Command:** `./fio-check.sh -r <tmpdir>/short_r.txt --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** exit `0`

### TC-13.18 — `-r` short alias — report file created

**Command:** `./fio-check.sh -r <tmpdir>/short_r.txt --dry-run run-lib foundries/lib_fioconfig.sh`  
**Expected:** file: `<tmpdir>/short_r.txt`

---

## Test Case Count

| Section | Description | Tests |
|---|---|---|
| 1 | Preconditions | 2 |
| 2 | Help / Usage | 12 |
| 3 | list-libs | 12 |
| 4 | list-profiles | 8 |
| 5 | check-cmd | 23 |
| 6 | check-kconfig | 9 |
| 7 | check-deps | 5 |
| 8 | run-lib | 21 |
| 9 | run-all-libs | 8 |
| 10 | run-all | 8 |
| 11 | load | 11 |
| 12 | Missing arguments | 7 |
| 13 | Option combinations | 18 |
| | **Total** | **144** |

| Type | Count |
|---|---|
| Fixed expectations (exit N) | 118 |
| System-dependent ⚠️ (exit 0\|1) | 26 |

---

## Out of Scope

The following are not covered by the automated script because they require specific hardware, a registered device, or external services. They should be verified manually on a real LmP device.

- Actual sysctl parameter values (`check-sysctl` live)
- TEE device node presence (`/dev/tee0`, `/dev/teepriv0`)
- RPMB partition check
- `fiovb_printenv` over a live OP-TEE session
- mTLS certificate expiry validation (`openssl x509 -checkend`)
- Foundries.io device registration state (`/var/sota/sql.db`)
- Docker daemon responsive check (`docker info`)
- Docker smoke test (`docker run hello-world`)
- systemd service enable/active state checks

These are exercised by `check_systemd_service`, `lib_fiovb_*`, `lib_fioconfig_*`, and `lib_docker_*` in the lib scripts.
