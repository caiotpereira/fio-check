#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_fioconfig.sh — configuration daemon (fioconfig)
#
# fioconfig fetches encrypted configuration from the update server and runs
# handlers when a file changes. Both layers install:
#   /usr/bin/fioconfig
#   fioconfig.service          daemon (ConditionPathExists=/var/sota/sota.toml)
#   fioconfig-extract.service  oneshot, decrypts /var/sota/config.encrypted
#   fioconfig.path             starts fioconfig once sota.toml exists
#   /usr/share/fioconfig/handlers/aktualizr-toml-update   restarts SOTA_CLIENT
# and RDEPEND on networkmanager-nmcli (FR-10).
#
# Expectations
#   FIOCHECK_FIOCONFIG_UNITS       units that must be enabled
#                                  (default: the three units above)
#   FIOCHECK_FIOCONFIG_HANDLERS    handler names that must be installed
#                                  (default: aktualizr-toml-update)
#   FIOCHECK_FIOCONFIG_ACTIONS     action names that must be installed (empty: skip)
#   FIOCHECK_SOTA_CLIENT           client the toml handler must restart
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_FIOCONFIG_LOADED:-}" ] && return 0
_LIB_FIOCONFIG_LOADED=1

: "${FIOCHECK_FIOCONFIG_UNITS:=fioconfig.service fioconfig-extract.service fioconfig.path}"
: "${FIOCHECK_FIOCONFIG_HANDLERS:=aktualizr-toml-update}"
: "${FIOCHECK_SOTA_CLIENT:=aktualizr-lite}"

_FIOCONFIG_SHARE="/usr/share/fioconfig"

lib_fioconfig_cmd() {
    check_cmd fioconfig "fioconfig"
}

# ---------------------------------------------------------------------------
# Handlers and actions; the toml handler restarts the configured client
# (FR-06: no hard-coded aktualizr-lite)
# ---------------------------------------------------------------------------
lib_fioconfig_handlers() {
    local rc=0 h
    for h in ${FIOCHECK_FIOCONFIG_HANDLERS}; do
        check_file "${_FIOCONFIG_SHARE}/handlers/${h}" f "fioconfig handler: ${h}" || rc=1
    done
    for h in ${FIOCHECK_FIOCONFIG_ACTIONS:-}; do
        check_file "${_FIOCONFIG_SHARE}/actions/${h}" f "fioconfig action: ${h}" || rc=1
    done
    local toml="${_FIOCONFIG_SHARE}/handlers/aktualizr-toml-update"
    if [ -f "$(fiocheck_path "${toml}")" ]; then
        check_file_contains "${toml}" "SOTA_CLIENT=${FIOCHECK_SOTA_CLIENT}([^A-Za-z0-9_-]|$)" \
            "aktualizr-toml-update restarts ${FIOCHECK_SOTA_CLIENT}" || rc=1
    fi
    return "${rc}"
}

lib_fioconfig_service() {
    local rc=0 u
    for u in ${FIOCHECK_FIOCONFIG_UNITS}; do
        check_systemd_unit "${u}" enabled || rc=1
    done
    return "${rc}"
}

# ---------------------------------------------------------------------------
# Runtime — after registration: daemon running, secrets tmpfs mounted
# ---------------------------------------------------------------------------
lib_fioconfig_runtime_check() {
    dry_run "lib_fioconfig_runtime_check (fioconfig state)" && return 0
    require_runtime "fioconfig runtime" || return 0
    if ! fiocheck_registered; then
        log_info "fioconfig: device not registered — daemon starts after registration"
        return 0
    fi
    local rc=0
    check_unit_active fioconfig.service "active|activating" || rc=1
    if awk '$2=="/var/run/secrets" || $2=="/run/secrets" { f=1 } END { exit !f }' /proc/mounts 2>/dev/null; then
        log_ok "fioconfig secrets: /var/run/secrets mounted"
    else
        log_warn "fioconfig secrets: /var/run/secrets not mounted — no configuration applied yet"
    fi
    if [ -f /var/sota/config.encrypted ]; then
        log_ok "fioconfig: /var/sota/config.encrypted present (configuration received)"
    else
        log_info "fioconfig: no configuration received yet (/var/sota/config.encrypted)"
    fi
    return "${rc}"
}

lib_fioconfig_all() {
    lib_fioconfig_cmd
    lib_fioconfig_handlers
    lib_fioconfig_service
    lib_fioconfig_runtime_check
}
