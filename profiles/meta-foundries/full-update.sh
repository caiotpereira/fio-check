#!/usr/bin/env sh
# =============================================================================
# Profile : meta-foundries/full-update — Foundries Full Update image
# Fixture : foundries-full   (tests/fixtures/make-rootfs.sh flavour for static validation)
#
# Foundries OS Update plus packagegroup-foundries-containers (D-12, FR-02):
# composectl (COMPOSE_APP_MANAGER) and, with meta-virtualization, docker and
# docker-compose with the layer's daemon.json.
#
#   ./fio-check.sh --expect blacksail --machine uno-q run-profile meta-foundries/full-update
# =============================================================================

: "${FIOCHECK_DOCKER_STORAGE_DRIVER:=overlay2}"
: "${FIOCHECK_DOCKER_DAEMON_JSON:=/usr/lib/docker/daemon.json}"

. "${FIOCHECK_PROFILE_DIR}/os-update.sh"
fiocheck_use docker composectl

fiocheck_run() {
    fiocheck_run_os_update

    fiocheck_req FR-02 "Container stack (docker, docker-compose)"
    lib_docker_all
    lib_docker_compose_all

    fiocheck_req FR-09 "App manager (composectl)"
    lib_composectl_cmd
    lib_composectl_cmd_version
    lib_composectl_files_check
    lib_composectl_runtime_check

    fiocheck_req FR-21 "App storage on the persistent /var"
    lib_composectl_storage_persistent
}
