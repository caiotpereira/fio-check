#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_fio_docker_fsck.sh — Docker store check and repair
#
# meta-lmp only today (FR-15, SHOULD). fio-docker-fsck.service runs
# `fio-docker-fsck -fix-store` before docker.service on every boot.
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_FIO_DOCKER_FSCK_LOADED:-}" ] && return 0
_LIB_FIO_DOCKER_FSCK_LOADED=1

lib_fio_docker_fsck_cmd() {
    check_cmd fio-docker-fsck "fio-docker-fsck"
}

# FR-15: the unit is enabled and ordered before docker.service
lib_fio_docker_fsck_service() {
    check_systemd_unit fio-docker-fsck.service enabled || return 1
    local d f=""
    for d in ${_unit_dirs}; do
        [ -f "$(fiocheck_path "${d}/fio-docker-fsck.service")" ] && { f="${d}/fio-docker-fsck.service"; break; }
    done
    [ -n "${f}" ] && check_file_contains "${f}" '^Before=.*docker\.service' \
        "fio-docker-fsck.service ordered before docker.service"
}

lib_fio_docker_fsck_all() {
    lib_fio_docker_fsck_cmd
    lib_fio_docker_fsck_service
}
