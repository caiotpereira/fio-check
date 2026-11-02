#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_aktualizr.sh — OTA client (aktualizr-lite or the client
# named by SOTA_CLIENT)
#
# meta-foundries: recipe aktualizr-lite_<pv>.bb (aktualizr-lite repo).
# meta-lmp:       built from the aktualizr recipe through a bbappend.
# Both install /usr/bin/aktualizr-lite, aktualizr-lite.service and a tmpfiles
# entry creating /var/sota with mode 0700.
#
# Expectations
#   FIOCHECK_SOTA_CLIENT           client binary and unit name (default aktualizr-lite)
#   FIOCHECK_AKLITE_COMMIT         7-char commit `aktualizr-lite --version` must
#                                  report (empty: report only)
#   FIOCHECK_AKLITE_OFFLINE        yes: aklite-offline required, no: must be
#                                  absent, empty: optional
#   FIOCHECK_AKLITE_LIBS           shared libraries that must be installed
#   FIOCHECK_AKLITE_CONF_DIR       default config directory (empty: skip)
#   FIOCHECK_AKLITE_HARDWARE_ID    expected primary_ecu_hardware_id in the
#                                  config directory (empty: skip)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_AKTUALIZR_LOADED:-}" ] && return 0
_LIB_AKTUALIZR_LOADED=1

: "${FIOCHECK_SOTA_CLIENT:=aktualizr-lite}"

# Kept for profiles written before the FIOCHECK_* variables
lib_aktualizr_set_version() { FIOCHECK_AKLITE_COMMIT="$1"; }

# ---------------------------------------------------------------------------
# Binary and commit
# ---------------------------------------------------------------------------
lib_aktualizr_cmd() {
    check_cmd "${FIOCHECK_SOTA_CLIENT}" || return 1
    [ "${FIOCHECK_SOTA_CLIENT}" = "aktualizr-lite" ] || return 0
    check_cmd_version aktualizr-lite "${FIOCHECK_AKLITE_COMMIT:-}" "--version" '[0-9a-f]{7}' true
}

# aklite-offline is built only with PACKAGECONFIG aklite-offline
lib_aktualizr_offline() {
    case "${FIOCHECK_AKLITE_OFFLINE:-}" in
        yes) check_cmd aklite-offline "aktualizr-lite PACKAGECONFIG aklite-offline" ;;
        no)  check_absent_cmd aklite-offline ;;
        *)
            dry_run "aklite-offline (optional)" && return 0
            if [ -n "$(_find_cmd aklite-offline)" ]; then
                log_info "aklite-offline: installed"
            else
                log_info "aklite-offline: not installed (optional)"
            fi ;;
    esac
}

lib_aktualizr_lib_check() {
    local rc=0 lib
    if [ -z "${FIOCHECK_AKLITE_LIBS:-}" ]; then
        log_skip "aktualizr libraries: no FIOCHECK_AKLITE_LIBS expectation"
        return 0
    fi
    for lib in ${FIOCHECK_AKLITE_LIBS}; do
        check_lib_dependency "${lib}" || rc=1
    done
    return "${rc}"
}

# ---------------------------------------------------------------------------
# Files — /var/sota (tmpfiles, 0700) and the default config directory
# ---------------------------------------------------------------------------
lib_aktualizr_files_check() {
    local rc=0
    check_file_mode /var/sota 700 || rc=1
    if [ -n "${FIOCHECK_AKLITE_CONF_DIR:-}" ]; then
        check_file "${FIOCHECK_AKLITE_CONF_DIR}" d || rc=1
        if [ -n "${FIOCHECK_AKLITE_HARDWARE_ID:-}" ]; then
            dry_run "hardware id in ${FIOCHECK_AKLITE_CONF_DIR}" && return "${rc}"
            local d; d="$(fiocheck_path "${FIOCHECK_AKLITE_CONF_DIR}")"
            local id; id="$(grep -hE '^[[:space:]]*primary_ecu_hardware_id' "${d}"/*.toml 2>/dev/null \
                | head -n 1 | cut -d= -f2 | tr -d ' "')"
            if [ "${id}" = "${FIOCHECK_AKLITE_HARDWARE_ID}" ]; then
                log_ok "Hardware ID: ${id}"
            else
                log_fail "Hardware ID: ${id:-not set} — expected ${FIOCHECK_AKLITE_HARDWARE_ID}"
                rc=1
            fi
        fi
    fi
    return "${rc}"
}

# ---------------------------------------------------------------------------
# Service — enabled; running once the device is registered
# (aktualizr-lite.service has ConditionPathExists=/var/sota/sota.toml)
# ---------------------------------------------------------------------------
lib_aktualizr_check_service() {
    check_systemd_unit "${FIOCHECK_SOTA_CLIENT}.service" enabled || return 1
    fiocheck_static && return 0
    dry_run "${FIOCHECK_SOTA_CLIENT} active state" && return 0
    if fiocheck_registered; then
        check_unit_active "${FIOCHECK_SOTA_CLIENT}.service" "active|activating"
    else
        log_info "${FIOCHECK_SOTA_CLIENT}: device not registered — the service starts after registration"
    fi
}

lib_aktualizr_all() {
    lib_aktualizr_cmd
    lib_aktualizr_offline
    lib_aktualizr_lib_check
    lib_aktualizr_files_check
    lib_aktualizr_check_service
}
