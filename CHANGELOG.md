# Changelog

All notable changes to fio-check are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html); before 1.0, a minor
version may change the command line.

## 0.2.0 — 2026-11-02

Commits `0bfb001`..`3827d07` on top of 0.1.0.

Reorganizes fio-check to validate images built with both meta-lmp and
meta-foundries, and makes it run unchanged on GPLv3-free images (busybox only).

### Breaking changes

- The command line is now `list`, `run` and `check`:

  | 0.1                                  | 0.2                                      |
  |--------------------------------------|------------------------------------------|
  | `list-profiles`, `list-libs`         | `list` (`-v` adds every lib function)    |
  | `run-profile <profile>`              | `run <layer>/<profile>`                  |
  | `run-lib <lib>`                      | `run <lib>` (e.g. `run docker`)          |
  | `--fn <function> run-lib <lib>`      | `run <lib>:<function>`                   |
  | `check-cmd`, `check-kconfig`, `check-deps` | `check cmd`, `check kconfig`, `check lib` |
  | `run-all`, `run-all-libs`            | removed — use `tests/validate-profiles.sh` in CI |

- Libs moved from `lib/` and `lib/foundries/` to `lib/components/`;
  `lib_lmp_device_register.sh` is now `lib_device_register.sh`.
- Profiles `foundries/lmp-v97` and `docker/docker` are removed. Use
  `run meta-lmp/lmp --expect v97` and `run docker`.
- Profiles define their checks in `fiocheck_run()` and set their defaults
  before sourcing the libs.

### Added

- Profiles by layer: `meta-foundries/os-update` (Foundries OS Update),
  `meta-foundries/full-update` (Foundries Full Update) and `meta-lmp/lmp`.
  meta-foundries results carry the ID of the program requirement each check
  proves (e.g. `[FR-08]`).
- Expectation sets (`profiles/<layer>/expect/`): meta-foundries `blacksail`
  and `wrynose`, meta-lmp `wrynose` and `v97`. Machine files
  (`profiles/meta-foundries/machine/`): `qemux86-64`, `qemuarm64-secureboot`,
  `uno-q`.
- `tools/gen-expect.sh`: generates an expectation set from a meta-foundries
  or meta-lmp checkout, optionally at a git ref, without touching the
  checkout.
- New libs: `lib_network` (NetworkManager, nmcli), `lib_system` (os-release,
  development credentials, free space, clock, watchdog), `lib_fio_diag`,
  `lib_fio_docker_fsck`, `lib_auto_hostname`.
- Options: `--expect`, `--machine`, `--root` (static checks against an
  unbooted rootfs), `--kconfig`, `--mode dev|production`, `--warn-as-fail`.
  Options are accepted before or after the command.
- Check helpers: `check_absent_cmd`, `check_file`, `check_absent_file`,
  `check_file_mode`, `check_file_contains`, `check_json_values`,
  `check_cert_expiry`, `check_systemd_unit` (any unit type; reads unit files
  and `.wants` links when systemd is not running), `check_unit_active`,
  `fiocheck_req`, `require_runtime`, `dry_run`.
- Warnings are counted and shown in the summary and the report. The report
  also records the mode, the expectation set and the machine.
- `tests/run-docker-tests.sh`: the test suite and the profile matrix in four
  containers — busybox with the OE-core configuration, busybox with the
  meta-lmp fragments, bash and dash.
- `tests/validate-profiles.sh`: every profile × expectation set × machine,
  each in its own process against a fixture rootfs, with its own report. New
  expectation sets and profiles join the matrix automatically.
- `tests/fixtures/make-rootfs.sh`: fixture rootfs trees for static tests.
- `test_fio_check.sh`: fixture-rootfs runs with injected faults, core check
  tests with stub commands, a portability lint, and `FIO_SHELL` to choose the
  shell that executes fio-check.
- README, including what kind and level of testing fio-check performs
  (ISTQB terms).

### Changed

- Libs are generic: every expected value comes from a
  `FIOCHECK_<COMPONENT>_<FIELD>` variable. An empty value means "report, don't
  enforce". The precedence is environment > machine > expectation set >
  profile > lib.
- Distro choices, such as the OSTree stateroot (`FIOCHECK_OSTREE_OSNAME`), are
  no longer assumed; the developer sets them.
- `lib_aktualizr`: `aklite-offline` is optional unless the expectation says
  otherwise. Checks `/var/sota` mode `0700`, the hardware id in
  `/usr/lib/sota/conf.d`, and that the service is running once the device is
  registered.
- `lib_fioconfig`: checks the three units (`fioconfig.service`,
  `fioconfig-extract.service`, `fioconfig.path`), the handlers and actions,
  and that the `aktualizr-toml-update` handler restarts the configured client.
- `lib_device_register`: works for `lmp-device-register` and
  `fio-device-register`. Fails when the legacy name is present on
  meta-foundries. Checks the identity files that `sota.toml` names, and the
  API token file mode.
- `lib_compose_apps_early_start`: accepts `enabled` or `disabled`, because the
  service disables itself after its first run.
- `lib_fiovb`: calls `fiovb_printenv`, and checks the trusted application in
  `/lib/optee_armtz`.
- `lib_docker`: checks `daemon.json` entries and the storage driver against
  the expectation set.

### Fixed

- `head -1` replaced with `head -n 1` everywhere. The OE-core busybox rejects
  the legacy form, which broke every systemd unit lookup and profile
  folder-name resolution on real images.
- `check_cmd_version` never enforced a minimum version: the default pattern
  captured the text before the number. It also executed commands that do not
  exist.
- `check_lib_dependency` matched substrings (any name containing "c" passed),
  doubled the `lib` prefix in its file search, and received install hints as
  the minimum version.
- `--dry-run` called an undefined `_dry_print` helper, logged OK for probes it
  skipped, and still ran `sysctl`.
- A missing kernel config made every kernel check pass. It is now a warning.
- Profile hooks were never called; `fiocheck_pre_hook` and
  `fiocheck_post_hook` now run around `fiocheck_run`.
- `set -e` was re-enabled after every run.
- The `report` command was accepted but did nothing.
- The test suite used `cat -v`, which the OE-core busybox does not provide.

### Removed

- `run-all`, `run-all-libs`, `--fn`, and the commands replaced above.
- The inline self-test blocks (`_FIO_TEST`) in `fio-check.sh`.
- `lib_network`'s connman check: NetworkManager and nmcli are what matter.

### Known issues

- None.

## 0.1.0 — 2026-05-28

First version, up to commit `27b6e21`. The script reported itself as `0.0.1`.

### Added

- `fio-check.sh` with the commands `list-profiles`, `list-libs`,
  `run-profile` (formerly `load`), `run-lib`, `run-all`, `run-all-libs`,
  `check-deps`, `check-kconfig` and `check-cmd`.
- Options `--verbose`, `--quiet`, `--no-color`, `--report`, `--filter`,
  `--fn`, `--dry-run`, `--profiles-dir` and `--lib-dir`.
- Check helpers `check_cmd`, `check_cmd_version`, `check_lib_dependency`,
  `check_kconfig`, `check_sysctl` and `check_systemd_service`, plus profile
  hooks and plain-text reports.
- Libs: `lib_docker`, `lib_aktualizr`, `lib_fioconfig`, `lib_composectl`,
  `lib_compose_apps_early_start`, `lib_fiovb` (aarch64 only),
  `lib_lmp_device_register` and `lib_ostree`.
- Profiles: `docker/docker` and `foundries/lmp-v97`.
- Ported from bash to POSIX sh.
- `test_fio_check.sh`, which exercises every command and option, and
  `test_plan.md`, which maps the test cases.

### Fixed

- Many fixes in the check helpers (pkg-config, sysctl, kconfig, systemd
  service state), the colors, the filter, profile resolution and report
  naming. `FIOCHECK_DRY_RUN` is now exported so the lib dry-run guards fire.

