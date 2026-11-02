# fio-check

fio-check checks that a device image built with
[meta-lmp](https://github.com/foundriesio/meta-lmp) or
[meta-foundries](https://github.com/foundriesio/meta-foundries) carries the
Foundries.io update stack the layer promises. That stack is the OTA client,
device registration, fioconfig, OSTree and, for Full Update images, the
container stack.

It runs in two places:

- **on the device**, over a serial console or SSH, checking the running system;
- **on the build host**, against the unbooted rootfs of a build (`--root`),
  before anything is flashed.

fio-check is POSIX `sh`. It runs under bash, dash and busybox ash with only
busybox applets, so it works on GPLv3-free images (`IMAGE_INCOMPATIBLE_LICENSE
= "GPL-3.0* ..."`), which have no bash and no GNU coreutils.

## Quick start

```sh
# On a device: Foundries Full Update image, wrynose pins, Arduino UNO Q
./fio-check.sh run meta-foundries/full-update --expect wrynose --machine uno-q

# On the build host: static checks against the build's rootfs
./fio-check.sh run meta-foundries/os-update --expect blacksail \
    --root tmp/work/<machine>/<image>/1.0/rootfs --kconfig <kernel>/.config

# An LmP image, LmP v97 pins, with a report file
./fio-check.sh run meta-lmp/lmp --expect v97 -r report.txt

# One component, or one check
./fio-check.sh run docker
./fio-check.sh run docker:daemon_config --expect meta-foundries/wrynose
./fio-check.sh check kconfig CONFIG_OVERLAY_FS y
```

`./fio-check.sh list` shows every profile, expectation set, machine file and
lib. `./fio-check.sh list -v` also shows every `<lib>:<function>`.

## Commands

| Command | Does |
|---|---|
| `list [-v]` | Profiles (with their expectation sets and machines) and libs |
| `run <target>` | Runs a profile (`meta-foundries/full-update`), a lib (`docker`, which runs `lib_docker_all`) or one function (`docker:daemon`, which runs `lib_docker_daemon`) |
| `check cmd\|kconfig\|lib\|sysctl <args>` | Runs one check, without a profile |

Options can come before or after the command:

| Option | Effect |
|---|---|
| `--expect <name>` | Expectation set: `profiles/<layer>/expect/<name>.sh`. For a lib, use `<layer>/<name>` when the name exists in more than one layer |
| `--machine <name>` | Machine file: `profiles/<layer>/machine/<name>.sh` |
| `--root <dir>` | Check an unbooted rootfs. Checks that need a running system report SKIP |
| `--kconfig <file>` | Kernel config to check (plain or `.gz`). Without one, kernel checks report a WARN, never a pass |
| `--mode dev\|production` | Turns on the production-only checks: no development user, no sudoers fragment, root locked, API token empty |
| `-r <file>` | Plain-text report |
| `--filter ok,fail,warn,skip,info` | Show only these result types |
| `--warn-as-fail` | A warning counts as a failure |
| `--dry-run` | List the checks without executing them |
| `-v`, `-q`, `--no-color` | Verbose, quiet, plain output |

Exit status: `0` no check failed, `1` at least one check failed, `2` usage error.

## How it is organized

The same components ship in both layers. They differ in names, pins and which
optional parts are present. The checks are therefore organized by component,
not by layer:

```
fio-check.sh                    check primitives and the runner
lib/components/lib_<name>.sh    one lib per component, generic: no versions, no layer values
profiles/<layer>/<profile>.sh   which components an image must (and must not) have
profiles/<layer>/expect/*.sh    pins for one layer release, generated from the layer
profiles/<layer>/machine/*.sh   per-machine values (hardware id)
tools/gen-expect.sh             layer checkout → expectation set
tests/                          fio-check's own tests
```

| Profile | Image |
|---|---|
| `meta-foundries/os-update` | Foundries OS Update: OTA client, fio-device-register, fioconfig, NetworkManager, OSTree. No container stack |
| `meta-foundries/full-update` | Foundries Full Update: OS Update plus docker, docker-compose, composectl and the layer's `daemon.json` |
| `meta-lmp/lmp` | The LmP `lmp` distro, plus the LmP-only parts: compose-apps-early-start, fio-docker-fsck, lmp-auto-hostname, fiovb on OP-TEE machines |

meta-foundries results carry the ID of the program requirement each check
proves, e.g. `[FR-08]`. meta-lmp results carry the component name.

### Expectations and precedence

A lib reads every expected value from a `FIOCHECK_<COMPONENT>_<FIELD>`
variable. An empty value means *report, don't enforce*. Every value is set
with `: "${VAR:=value}"`, so the first one set wins:

1. the environment, e.g. `FIOCHECK_SOTA_CLIENT=my-client ./fio-check.sh run ...`
2. the machine file (`--machine`)
3. the expectation set (`--expect`)
4. the profile defaults
5. the lib defaults (component facts shared by both layers)

Distro choices are the developer's and fio-check does not assume them. For
example, set `FIOCHECK_OSTREE_OSNAME` to have the OSTree stateroot checked.

### Expectation sets

Expectation sets are generated, not hand-written. Regenerate one when the
layer moves a pin; the diff of the generated file is what gets reviewed.

```sh
tools/gen-expect.sh ../meta-foundries profiles/meta-foundries/expect/blacksail.sh
tools/gen-expect.sh ../meta-foundries profiles/meta-foundries/expect/wrynose.sh origin/wrynose
tools/gen-expect.sh ../meta-lmp       profiles/meta-lmp/expect/wrynose.sh
```

The optional git ref reads the layer at that branch, tag or commit and leaves
the checkout untouched. To support a new release, for example LmP v98, add
`profiles/meta-lmp/expect/v98.sh`. It appears in `list`, works with `--expect
v98`, and the CI matrix picks it up without further changes.

### Writing a profile

```sh
# Fixture : foundries-full     (rootfs flavour used by tests/validate-profiles.sh)
: "${FIOCHECK_DOCKER_STORAGE_DRIVER:=overlay2}"   # defaults first ...
. "${FIO_TEST_LIB}/components/lib_docker.sh"      # ... then the libs

fiocheck_run() {
    fiocheck_req FR-02 "Container stack"          # tag the results that follow
    lib_docker_all
    check_absent_cmd fioup
}
```

`fiocheck_pre_hook` and `fiocheck_post_hook`, when defined, run around
`fiocheck_run`.

### Writing a lib

Name each function `lib_<component>_<aspect>` and make it runnable alone
(`run <component>:<aspect>`). Build checks from the core helpers:
- `check_cmd`, `check_absent_cmd`, `check_cmd_version`
- `check_file`, `check_file_mode`, `check_file_contains`, `check_json_values`
- `check_systemd_unit`, `check_unit_active`
- `check_kconfig`, `check_lib_dependency`, `check_cert_expiry`

They handle `--root` and `--dry-run` themselves. A check that needs a running
system starts with `require_runtime "<what>" || return 0`. Use only POSIX sh
and busybox options: `head -n 1`, not `head -1`.

## What kind of testing this is (ISTQB)

Classified with the ISTQB Certified Tester Foundation Level (v4.0) terms.

**Test object.** A built device image: its rootfs, or the running device.
Each lib is named after a component, but the component is never the test
object.

**Test level: system testing, with component-integration checks. Not
component testing.**

- *Component testing* checks one component in isolation, against its
  detailed design, usually with its source code and test doubles. Examples
  are aktualizr-lite's or composectl's own unit tests in their repositories.
  fio-check never isolates a component and never exercises its internal
  logic.
- *System testing* checks the integrated system against its specification.
  That is what fio-check does to the image. Does the image contain the
  components its tier requires, and not the ones it forbids (OS Update: no
  container stack)? Are they installed, configured, enabled and running as
  the layer's recipes define?
- *Component integration testing* covers the interfaces between components
  inside the image. Some checks are of this kind:
  - fioconfig's handler restarts the client named by `SOTA_CLIENT`;
  - composectl reaches dockerd through its socket;
  - the OTA client's state lives on the persistent `/var`;
  - the booted deployment matches the expected OSTree stateroot.
- It is *not system integration testing*: it does not exercise the update
  server, the registry or other external systems. It is *not acceptance
  testing* either, but its reports are objective evidence for acceptance and
  release checklists.

**Test types.**

- *Functional*, specification-based (black-box). The test basis is the layer
  recipes, which supply the expectation sets, and the program requirements,
  which supply the requirement tags. Most checks are installation and
  configuration checks.
- *Non-functional*, checked as configuration, not measured:
  - security: no development credentials in production images, file modes
    `0700`/`0600`, certificate expiry;
  - reliability prerequisites: watchdog, free space for updates, a
    synchronized clock;
  - portability: runs on GPLv3-free busybox images.
- *Change-related*: regression testing. Every layer release has an expectation
  set, and the CI matrix re-checks every profile against every set.
  Confirmation testing re-runs a single profile after a fix.

**Static and dynamic.**

- `--root` is *static testing*: it examines a work product (the build
  output) without executing it, so it fits the per-PR build gate.
- On a device fio-check is *dynamic*, but it observes the system more than
  it stimulates it. It is a *smoke test* (build verification) of the image:
  boot, services and composition-specific health.

**What it does not cover.** Behavior over time and under faults: an OTA
update cycle, rollback after a failed boot, power loss mid-update, TUF
metadata expiry, certificate renewal. Those are dynamic system and
system-integration scenarios that need a test harness to drive the device
(flash, reboot, inject faults). fio-check's libs are meant to be called from
such a harness as its on-device assertions.

**fio-check's own tests** are a different test object: fio-check itself.
- `test_fio_check.sh` is component and component-integration testing of
  fio-check, using stub commands and fixture rootfs trees;
- `tests/validate-profiles.sh` is regression testing of the profiles and
  expectation sets.

## Testing fio-check

```sh
./test_fio_check.sh [-v]                  # suite, on this host
FIO_SHELL=dash ./test_fio_check.sh        # fio-check executed by another shell
tests/validate-profiles.sh [-v]           # every profile x expectation set x machine
tests/run-docker-tests.sh [target ...]    # both, in containers
```

`tests/run-docker-tests.sh` runs the suite and the profile matrix in four
containers:

| Target | Userland |
|---|---|
| `busybox-oe` | scratch image with a static busybox built from the OE-core busybox configuration (meta-foundries / nodistro) |
| `busybox-lmp` | the same plus the meta-lmp busybox fragments |
| `bash`, `dash` | Debian, with fio-check executed by that shell |

The busybox targets reproduce what a real image rejects, such as `head -1`
and `cat -v`, which the host's busybox may still accept.

`tests/validate-profiles.sh` builds a fixture rootfs for each combination
(`tests/fixtures/make-rootfs.sh`) and runs each one as its own process with
its own report. A failing combination never hides the others, and it prints
the command that reproduces it alone.

## License

MIT — see [LICENSE](LICENSE).
