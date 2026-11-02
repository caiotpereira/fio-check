#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_compose_apps_early_start.sh — preloaded app launcher
#
# meta-lmp only (not in meta-foundries; FR-13 is a SHOULD). Starts preloaded
# Compose Apps on first boot, before registration:
#   /usr/bin/compose-apps-early-start            oneshot script
#   /usr/bin/compose-apps-early-start-recovery   store recovery script
#   compose-apps-early-start.service             ConditionPathExists=!/var/sota/sql.db,
#                                                disables itself after it runs
#   compose-apps-early-start-recovery.service
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_COMPOSE_APPS_EARLY_START_LOADED:-}" ] && return 0
_LIB_COMPOSE_APPS_EARLY_START_LOADED=1

lib_compose_apps_early_start_cmd() {
    local rc=0
    check_file /usr/bin/compose-apps-early-start x || rc=1
    check_file /usr/bin/compose-apps-early-start-recovery x || rc=1
    return "${rc}"
}

# Preloaded apps (informational: an image may ship none)
lib_compose_apps_early_start_files() {
    dry_run "lib_compose_apps_early_start_files (preloaded apps)" && return 0
    local store n found=0
    for store in /var/sota/reset-apps /var/sota/compose-apps; do
        [ -d "$(fiocheck_path "${store}")" ] || continue
        n="$(find "$(fiocheck_path "${store}")" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
        [ "${n}" -gt 0 ] && { log_info "Preloaded apps in ${store}: ${n}"; found=1; }
    done
    [ "${found}" -eq 1 ] || log_info "No preloaded apps in the image"
}

# The service disables itself after its first run, so both states are valid
lib_compose_apps_early_start_service() {
    local rc=0
    check_systemd_unit compose-apps-early-start.service "enabled|disabled" || rc=1
    check_systemd_unit compose-apps-early-start-recovery.service || rc=1
    return "${rc}"
}

lib_compose_apps_early_start_all() {
    lib_compose_apps_early_start_cmd
    lib_compose_apps_early_start_files
    lib_compose_apps_early_start_service
}
