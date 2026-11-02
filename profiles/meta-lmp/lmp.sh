#!/usr/bin/env sh
# =============================================================================
# Profile : meta-lmp/lmp — image built with the LmP "lmp" distro
# Fixture : lmp   (tests/fixtures/make-rootfs.sh flavour for static validation)
#
# The meta-lmp baseline: OSTree, aktualizr-lite, lmp-device-register,
# fioconfig, the container stack, and the LmP-only helpers
# (compose-apps-early-start, fio-docker-fsck, lmp-auto-hostname, and fiovb on
# OP-TEE machines).
#
#   ./fio-check.sh --expect wrynose run-profile meta-lmp/lmp
#   ./fio-check.sh --expect v97     run-profile meta-lmp/lmp
#
# Environment
#   FIOCHECK_FIOVB   yes | no | auto (default: auto — checked when the
#                    fiovb client is installed)
# =============================================================================

# ---------------------------------------------------------------------------
# meta-lmp layout. Defaults are set before the libs are sourced so they take
# precedence over the libs' own; --expect, --machine and the environment win.
# ---------------------------------------------------------------------------
: "${FIOCHECK_SOTA_CLIENT:=aktualizr-lite}"
: "${FIOCHECK_REGISTER_BIN:=lmp-device-register}"
: "${FIOCHECK_REGISTER_TOKEN_FILE:=/etc/lmp-device-register-token}"
: "${FIOCHECK_DOCKER_STORAGE_DRIVER:=overlay2}"
: "${FIOCHECK_DEV_USERS:=fio}"
: "${FIOCHECK_FIOVB:=auto}"

fiocheck_use aktualizr fioconfig device_register ostree docker composectl network \
             compose_apps_early_start fio_docker_fsck auto_hostname fio_diag fiovb system

fiocheck_run() {
    fiocheck_req aktualizr-lite "OTA client"
    lib_aktualizr_all

    fiocheck_req fioconfig "Configuration daemon"
    lib_fioconfig_all
    lib_network_all

    fiocheck_req lmp-device-register "Device registration"
    lib_device_register_all

    fiocheck_req ostree "OSTree deployment"
    lib_ostree_all

    fiocheck_req containers "Docker and composectl"
    lib_docker_all
    lib_docker_compose_all
    lib_composectl_all

    fiocheck_req compose-apps-early-start "Preloaded apps launcher"
    lib_compose_apps_early_start_all

    fiocheck_req fio-docker-fsck "Docker store check"
    lib_fio_docker_fsck_all

    fiocheck_req lmp-auto-hostname "Hostname"
    lib_auto_hostname_all

    fiocheck_req fio-diag "Support bundle"
    lib_fio_diag_all

    fiocheck_req fiovb "OP-TEE boot variables"
    case "${FIOCHECK_FIOVB}" in
        yes) lib_fiovb_all ;;
        no)  log_skip "fiovb: disabled (FIOCHECK_FIOVB=no)" ;;
        *)
            if [ -n "$(_find_cmd fiovb)" ]; then
                lib_fiovb_all
            else
                log_skip "fiovb: not installed (not an OP-TEE / U-Boot machine)"
            fi ;;
    esac

    fiocheck_req system "Image-wide checks"
    lib_system_all
}
