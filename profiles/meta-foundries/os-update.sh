#!/usr/bin/env sh
# =============================================================================
# Profile : meta-foundries/os-update — Foundries OS Update image
# Fixture : foundries-os   (tests/fixtures/make-rootfs.sh flavour for static validation)
#
# packagegroup-foundries-platform alone (D-12): the OTA client named by
# SOTA_CLIENT, fio-device-register and fioconfig, on an OSTree deployment,
# and no container stack (FR-01).
#
# Pins come from an expectation set, machine values from a machine file:
#   ./fio-check.sh --expect blacksail --machine qemux86-64 \
#       run-profile meta-foundries/os-update
#   ./fio-check.sh --root <rootfs> --expect blacksail run-profile meta-foundries/os-update
#
# Requirement IDs refer to the meta-foundries program requirements register.
# =============================================================================

# ---------------------------------------------------------------------------
# meta-foundries layout. Defaults are set before the libs are sourced so they
# take precedence over the libs' own; --expect, --machine and the environment
# win over both.
# ---------------------------------------------------------------------------
: "${FIOCHECK_SOTA_CLIENT:=aktualizr-lite}"
: "${FIOCHECK_AKLITE_CONF_DIR:=/usr/lib/sota/conf.d}"
: "${FIOCHECK_REGISTER_BIN:=fio-device-register}"
: "${FIOCHECK_REGISTER_ABSENT_BINS:=lmp-device-register}"
: "${FIOCHECK_FIOCONFIG_HANDLERS:=aktualizr-toml-update renew-client-cert fioconfig-oneshot}"
: "${FIOCHECK_FIOCONFIG_ACTIONS:=diag reboot}"
: "${FIOCHECK_OS_RELEASE:=LMP_FACTORY_TAG}"
: "${FIOCHECK_DEV_USERS:=foundries fio}"

. "${FIO_TEST_LIB}/components/lib_aktualizr.sh"
. "${FIO_TEST_LIB}/components/lib_fioconfig.sh"
. "${FIO_TEST_LIB}/components/lib_device_register.sh"
. "${FIO_TEST_LIB}/components/lib_ostree.sh"
. "${FIO_TEST_LIB}/components/lib_network.sh"
. "${FIO_TEST_LIB}/components/lib_fio_diag.sh"
. "${FIO_TEST_LIB}/components/lib_system.sh"

# The container stack an OS Update image must not carry (FR-01)
_OS_UPDATE_ABSENT="docker dockerd containerd composectl aklite-apps fioup"

fiocheck_run_os_update() {
    fiocheck_req FR-08 "OTA client (aktualizr-lite)"
    lib_aktualizr_all

    fiocheck_req FR-10 "Configuration daemon (fioconfig) and nmcli"
    lib_fioconfig_all
    lib_network_all

    fiocheck_req FR-11 "Device registration (fio-device-register, D-18)"
    lib_device_register_all

    fiocheck_req FR-22 "Registration tag in os-release"
    lib_system_os_release

    fiocheck_req TR-07 "OSTree deployment and stateroot"
    lib_ostree_all

    fiocheck_req FR-17 "Support bundle (fio-diag)"
    lib_fio_diag_all

    fiocheck_req SR-13 "Development credentials (--mode production)"
    lib_system_dev_credentials

    fiocheck_req TR-10 "Storage"
    lib_system_storage

    fiocheck_req TR-09 "Clock"
    lib_system_clock

    fiocheck_req FR-25 "Watchdog"
    lib_system_watchdog
}

fiocheck_run() {
    fiocheck_run_os_update

    fiocheck_req FR-01 "OS Update carries no container stack"
    # shellcheck disable=SC2086
    check_absent_cmd ${_OS_UPDATE_ABSENT}
}
