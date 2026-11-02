#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_auto_hostname.sh — hostname derived from the machine
#
# meta-lmp only today (FR-16, SHOULD): lmp-auto-hostname.service runs
# /usr/bin/lmp-update-hostname, which sets <machine>-<serial|mac>.
#
# Expectations
#   FIOCHECK_HOSTNAME_PREFIX   hostname prefix, usually the machine name
#                              (empty: report only)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_AUTO_HOSTNAME_LOADED:-}" ] && return 0
_LIB_AUTO_HOSTNAME_LOADED=1

lib_auto_hostname_cmd() {
    check_file /usr/bin/lmp-update-hostname x
}

lib_auto_hostname_service() {
    check_systemd_unit lmp-auto-hostname.service enabled
}

lib_auto_hostname_runtime() {
    dry_run "hostname prefix" && return 0
    require_runtime "hostname" || return 0
    local h; h="$(uname -n)"
    local prefix="${FIOCHECK_HOSTNAME_PREFIX:-}"
    if [ -z "${prefix}" ]; then
        log_info "Hostname: ${h}"
        return 0
    fi
    case "${h}" in
        "${prefix}"-*) log_ok "Hostname: ${h} (${prefix}-<id>)" ;;
        *) log_fail "Hostname: ${h} — expected ${prefix}-<serial|mac>"; return 1 ;;
    esac
}

lib_auto_hostname_all() {
    lib_auto_hostname_cmd
    lib_auto_hostname_service
    lib_auto_hostname_runtime
}
