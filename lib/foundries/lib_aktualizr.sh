#!/usr/bin/env sh
# =============================================================================
# lib/foundries/lib_aktualizr.sh — Foundries.io OTA Client - Aktualizr-lite
#
# Sourced by profiles; never executed directly.
# =============================================================================


[ -n "${_LIB_AKTUALIZR_LOADED:-}" ] && return 0
_LIB_AKTUALIZR_LOADED=1

# _AKLITE_VERSION="067a72f"
_AKLITE_VERSION="0"
#Check aktualizr-lite command
lib_aktualizr_cmd() {
    check_cmd "aktualizr-lite"
    check_cmd_version "aktualizr-lite" ${_AKLITE_VERSION} "--version" '[0-9a-f]{7}$' true
    #check aktualizr-offline (Optional)
    check_cmd "aklite-offline"
}

#Since aktualizr-lite has a hash as version
#the setter function can define the specific hash
lib_aktualizr_set_version(){
    _AKLITE_VERSION="$1"
}

# ---------------------------------------------------------------------------
# Aktualizr-lite — Required shared libraries check
# https://github.com/foundriesio/meta-lmp/blob/main/meta-lmp-base/recipes-sota/aktualizr/aktualizr_%25.bbappend
#
lib_aktualizr_lib_check() {
    check_lib_dependency libaktualizr_lite
    check_lib_dependency libfyaml
    check_lib_dependency libsqlite3
    check_lib_dependency libsodium
    check_lib_dependency libmount
    check_lib_dependency libarchive
}

lib_aktualizr_files_check() {
    local fio_docker_config="/usr/lib/docker/config.json"
    local fio_var="/var/sota/"
    local fio_etc="/etc/sota/conf.d/"

    #Check if the fio_docker_config exists
    if [ ! -e "${fio_docker_config}" ]; then
        log_fail "Could not find: ${fio_docker_config}"
    else
        log_ok "Check: ${fio_docker_config}"
    fi
    if [ -e "${fio_var}" ]; then
        local fio_var_perm
        fio_var_perm=$(stat -c '%a' "${fio_var}")
        if [ "${fio_var_perm}" = "700" ]; then
            log_ok "Folder permission: ${fio_var} = ${fio_var_perm}"
        else
            log_fail "Invalid folder permission: ${fio_var} = ${fio_var_perm} (expected 700)"
        fi
    else
        log_fail "Could no find ${fio_var}"
    fi
    if [ ! -e "${fio_etc}" ]; then
        log_fail "Could not find: ${fio_etc}"
    else
        log_ok "Check: ${fio_etc}"
    fi
    return 0
}

lib_aktualizr_check_service(){
    check_systemd_service "aktualizr-lite" "enabled"
}
