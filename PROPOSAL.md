# Proposal — organizing fio-check libs and profiles for meta-lmp and meta-foundries

fio-check must answer two questions about a device image:

1. **Is the meta-lmp image correct?** The image matches what `foundriesio/meta-lmp` builds.
   This is the regression baseline and the reference for the meta-lmp → meta-foundries
   parity checklist (UC-05).
2. **Is meta-foundries implemented correctly?** The image matches what the meta-foundries
   recipes declare, *and* it satisfies the program requirements (FR/SR/TR IDs in
   `meta-foundries-program`).

Both layers ship the same components (aktualizr-lite, composectl, fioconfig, the
device-register tool, ostree, docker). They differ in names, pins, paths, and which optional
components are present. The checks are therefore organized **by component, not by layer**.

## Four pieces

| Piece | Location | Holds | Changes when |
|---|---|---|---|
| Core | `fio-check.sh` | Check primitives and the runner | Rarely |
| Libs | `lib/components/` | One file per component. Generic: no versions, no layer values | Component behavior changes |
| Expectations | `profiles/<layer>/expect/<set>.sh` | Data only: commits, versions, paths, unit names. Generated from the layer source | The layer moves a pin |
| Profiles | `profiles/<layer>/<profile>.sh` | Composition: which components must be present or absent, tagged with the requirement each check proves | A tier definition changes |

## Layout

```
fio-check.sh                          core primitives + runner
lib/components/
  lib_docker.sh                       docker engine, compose, daemon config
  lib_network.sh                      NetworkManager / connman
  lib_system.sh                       os-release, dev users (SR-13), storage (TR-10),
                                      certificate expiry (TR-11), watchdog (FR-25)
  lib_aktualizr.sh  lib_composectl.sh  lib_fioconfig.sh  lib_ostree.sh  lib_fio_diag.sh
  lib_device_register.sh              lmp-device-register or fio-device-register (by expectation)
  lib_compose_apps_early_start.sh  lib_fiovb.sh                 (meta-lmp only today)
  lib_fio_docker_fsck.sh  lib_auto_hostname.sh                  (meta-lmp only today)
profiles/
  docker/docker.sh                    generic docker validation (no layer values)
  meta-lmp/
    expect/wrynose.sh                 generated from meta-lmp (main is wrynose)
    expect/v97.sh                     legacy LmP v97 pins
    lmp.sh                            "lmp" distro image (ostree + containers)
  meta-foundries/
    expect/blacksail.sh               generated from meta-foundries
    machine/<machine>.sh              per-machine values (hardware id, osname)
    os-update.sh                      Foundries OS Update
    full-update.sh                    Foundries Full Update = OS Update + container stack
tools/gen-expect.sh                   layer checkout → expect/<set>.sh
tests/                                host CI tests: fixtures and stub binaries
```

Profile discovery skips the `expect/` and `machine/` directories: they are data, not profiles.

## Lib contract

- **No values in libs.** Every expectation is a `FIOCHECK_<COMPONENT>_<FIELD>` variable.
  Empty means *report, don't enforce*. `none` means *must be absent*.
- **Naming:** `lib_<component>_{cmd,version,files,service,config,kconfig,runtime,all}`.
  Any function runs alone with `--fn` and returns a meaningful exit code.
- **Static vs runtime.** Static checks inspect files, modes, unit enablement, os-release and
  users; they work against an unbooted rootfs (`--root`). Runtime checks need a booted system
  (active units, `docker info`, `/proc`); with `--root` they report SKIP.
- **Requirement tags.** A profile calls `fiocheck_req FR-10` and every result logged after it
  carries the tag, so reports map to the program's acceptance criteria.

## Profile contract

- A profile declares expectations with `: "${FIOCHECK_X:=value}"` so the environment (CI)
  can override any value, and puts its checks in `fiocheck_run()`.
- The runner sources the expectation set (`--expect`), the machine file (`--machine`), then the
  profile, and calls `fiocheck_pre_hook` → `fiocheck_run` → `fiocheck_post_hook`.

```sh
# profiles/meta-foundries/full-update.sh
. "${FIO_TEST_PROFILES}/meta-foundries/os-update.sh"
fiocheck_run() {
    fiocheck_run_os_update
    fiocheck_req FR-02; lib_docker_all
    fiocheck_req FR-09; lib_composectl_all
}
```

## Parameters that differ between the layers

| Parameter | meta-lmp | meta-foundries |
|---|---|---|
| `FIOCHECK_OSTREE_OSNAME` | `lmp` | `nodistro` or the vendor distro's (TR-07) |
| `FIOCHECK_REGISTER_BIN` | `lmp-device-register` | `fio-device-register`; legacy name absent (D-18) |
| `FIOCHECK_SOTA_CLIENT` | `aktualizr-lite` | `aktualizr-lite`, overridable (FR-05, FR-06) |
| compose-apps-early-start, fio-docker-fsck, lmp-auto-hostname | present | not in the layer: SKIP (FR-13, FR-15, FR-16 are SHOULD) |
| optee-fiovb | U-Boot machines | out of scope (SR-01 descoped) |
| `/usr/lib/docker/daemon.json` | not installed | overlay2, snapshotter off, 3 downloads, 5 attempts |

## Usage

```sh
# Device (serial or SSH): L2 smoke and MVP evidence
./fio-check.sh --expect blacksail --machine qemux86-64 run-profile meta-foundries/full-update
# CI after bitbake, no device: static checks against the built rootfs (L1)
./fio-check.sh --root <rootfs> --kconfig <kernel .config> --expect blacksail \
               run-profile meta-foundries/os-update
# meta-lmp baseline
./fio-check.sh --expect wrynose run-profile meta-lmp/lmp
```

## Expectation generation

`tools/gen-expect.sh <layer-checkout> <layer-name>` reads SRCREV, PV, SRCBRANCH, SYSTEMD_SERVICE,
the `layer.conf` defaults and OSTREE_OSNAME, and writes `expect/<series>.sh`. Generated files
are committed and regenerated when a layer moves a pin, so pin changes show up as reviewable
diffs. A build's buildhistory (installed package list per image) is the more accurate source
and is a planned extension.

## Order of work

1. Core: `fiocheck_run` contract and hooks, `--expect`/`--machine`/`--root`/`--kconfig`,
   `check_absent`, `check_file_mode`, requirement tags, `check_cmd_version` fix.
2. Move libs to `lib/components/` and convert them to the contract (docker first).
3. `tools/gen-expect.sh` for both layers.
4. Profiles: `meta-foundries/os-update` and `full-update`, then `meta-lmp/lmp`.
5. CI: static rootfs checks in the per-PR build; BATS wrappers for on-board runs (D-11).
