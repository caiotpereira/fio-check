#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_network.sh — NetworkManager and nmcli
#
# fioconfig's network and VPN handlers drive NetworkManager through nmcli
# (FR-10). meta-foundries installs packagegroup-foundries-network
# (networkmanager, networkmanager-nmcli); meta-lmp's fioconfig RDEPENDS on
# networkmanager-nmcli.
#
# Expectations
#   FIOCHECK_NETWORK_UNITS   units that must be enabled
#                            (default NetworkManager.service)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_NETWORK_LOADED:-}" ] && return 0
_LIB_NETWORK_LOADED=1

: "${FIOCHECK_NETWORK_UNITS:=NetworkManager.service}"

lib_network_cmd() {
    local rc=0
    check_cmd NetworkManager "networkmanager" || rc=1
    check_cmd nmcli "networkmanager-nmcli" || rc=1
    return "${rc}"
}

lib_network_service() {
    local rc=0 u
    for u in ${FIOCHECK_NETWORK_UNITS}; do
        check_systemd_unit "${u}" enabled || rc=1
    done
    return "${rc}"
}

lib_network_runtime() {
    dry_run "nmcli general status" && return 0
    require_runtime "NetworkManager state" || return 0
    command -v nmcli >/dev/null 2>&1 || { log_skip "nmcli: not installed"; return 0; }
    local state; state="$(nmcli -t -f STATE general 2>/dev/null)"
    case "${state}" in
        connected*) log_ok "NetworkManager: ${state}" ;;
        "")         log_fail "NetworkManager: not running (nmcli general failed)"; return 1 ;;
        *)          log_warn "NetworkManager: ${state}" ;;
    esac
}

lib_network_all() {
    lib_network_cmd
    lib_network_service
    lib_network_runtime
}
