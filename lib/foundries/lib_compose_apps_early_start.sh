#!/usr/bin/env bash
# =============================================================================
# lib/foundries/lib_compose_apps_early_start.sh
#     compose-apps-early-start — preloaded compose app launcher
#
# Purpose
#   Starts preloaded Docker Compose Apps on first boot, before aktualizr-lite
#   runs and before device registration.  This allows containers to be
#   available without network access or a Foundries.io Factory connection.
#
#   The service is a systemd oneshot that only executes when the device is
#   NOT yet registered (/var/sota/sql.db absent).  After registration,
#   aktualizr-lite takes over app management.
#
# Installed files (from meta-lmp recipe)
#   /usr/bin/compose-apps-early-start      shell script (ExecStart)
#   /usr/lib/systemd/system/
#     compose-apps-early-start.service     main oneshot service
#
# Runtime files (created at runtime, not by OSTree)
#   /var/lmp/default-apps    newline-separated list of apps to start
#                            (optional — if absent, all preloaded apps start)
#
# Preloaded app locations (checked by the script)
#   /var/sota/reset-apps/<app>/    restorable apps (default since LmP v85)
#   /var/sota/compose-apps/<app>/  legacy compose type
#
# References
#   https://github.com/foundriesio/meta-lmp/tree/main/meta-lmp-base/
#           recipes-support/compose-apps-early-start
#   https://docs.foundries.io/latest/user-guide/containers-and-docker/
#           container-preloading.html
#
# Sourced by profiles; never executed directly.
# =============================================================================

[[ -n "${_LIB_COMPOSE_APPS_EARLY_START_LOADED:-}" ]] && return 0
_LIB_COMPOSE_APPS_EARLY_START_LOADED=1

# ---------------------------------------------------------------------------
# lib_compose_apps_early_start_cmd — binary check
# ---------------------------------------------------------------------------
lib_compose_apps_early_start_cmd() {
    check_cmd compose-apps-early-start \
        "compose-apps-early-start (meta-lmp / add to CORE_IMAGE_BASE_INSTALL)"
}

# ---------------------------------------------------------------------------
# lib_compose_apps_early_start_files — installed and runtime file checks
# ---------------------------------------------------------------------------
lib_compose_apps_early_start_files() {
    if [[ "${TESTFW_DRY_RUN:-0}" -eq 1 ]]; then
        _dry_print "lib_compose_apps_early_start_files (dry-run: filesystem probes skipped)"
        return 0
    fi

    # ── Installed script ─────────────────────────────────────────────────────
    local script="/usr/bin/compose-apps-early-start"
    if [[ -f "${script}" ]]; then
        log_ok "Script installed: ${script}"
    else
        log_warn "Script not found: ${script} — recipe not included in image"
    fi

    # ── Runtime app list (/var/lmp/default-apps) ─────────────────────────────
    # Created at runtime — absence means all preloaded apps will be started.
    local default_apps="/var/lmp/default-apps"
    if [[ -f "${default_apps}" ]]; then
        local app_count; app_count="$(grep -c '.' "${default_apps}" 2>/dev/null || echo 0)"
        log_ok "App list: ${default_apps} (${app_count} app(s) configured)"
        while IFS= read -r app; do
            [[ -n "${app}" ]] && log_info "  app: ${app}"
        done < "${default_apps}"
    else
        log_warn "App list not found: ${default_apps} — all preloaded apps will be started (file created at runtime)"
    fi

    # ── Preloaded app store presence ─────────────────────────────────────────
    local found_any=0
    for store in /var/sota/reset-apps /var/sota/compose-apps; do
        if [[ -d "${store}" ]]; then
            local count; count="$(find "${store}" -mindepth 1 -maxdepth 1 \
                -type d 2>/dev/null | wc -l)"
            if [[ "${count}" -gt 0 ]]; then
                log_ok "Preloaded apps in ${store}: ${count} app(s)"
                found_any=1
            else
                log_info "App store empty: ${store}"
            fi
        fi
    done
    if [[ "${found_any}" -eq 0 ]]; then
        log_warn "No preloaded apps found in /var/sota/reset-apps or /var/sota/compose-apps"
    fi
}

# ---------------------------------------------------------------------------
# lib_compose_apps_early_start_service — systemd service checks
# ---------------------------------------------------------------------------
lib_compose_apps_early_start_service() {
    # Main early-start service
    check_systemd_service "compose-apps-early-start" "enabled"
}

# ---------------------------------------------------------------------------
# lib_compose_apps_early_start_all — full check suite
# ---------------------------------------------------------------------------
lib_compose_apps_early_start_all() {
    lib_compose_apps_early_start_cmd
    lib_compose_apps_early_start_files
    lib_compose_apps_early_start_service
}
