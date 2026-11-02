#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_composectl.sh — Compose App manager (composectl)
#
# composectl is a statically linked Go CLI from github.com/foundriesio/composeapp.
# aktualizr-lite calls it to fetch, install and run Compose Apps; it has no
# daemon of its own. Both layers install /usr/bin/composectl and the
# aklite-apps symlink (package composectl-aklite-apps in meta-foundries).
#
# App storage (compiled-in defaults, on the persistent /var — FR-21):
#   /var/sota/reset-apps     app store (restorable apps)
#   /var/sota/compose-apps   compose projects
#
# Expectations
#   FIOCHECK_COMPOSECTL_COMMIT     commit prefix `composectl version` must
#                                  report (empty: report only)
#   FIOCHECK_COMPOSECTL_ALIAS      yes: aklite-apps symlink required (default yes)
#   FIOCHECK_COMPOSECTL_STORE      app store dir (default /var/sota/reset-apps)
#   FIOCHECK_COMPOSECTL_COMPOSE    compose dir   (default /var/sota/compose-apps)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_COMPOSECTL_LOADED:-}" ] && return 0
_LIB_COMPOSECTL_LOADED=1

: "${FIOCHECK_COMPOSECTL_ALIAS:=yes}"
: "${FIOCHECK_COMPOSECTL_STORE:=/var/sota/reset-apps}"
: "${FIOCHECK_COMPOSECTL_COMPOSE:=/var/sota/compose-apps}"

lib_composectl_cmd() {
    local rc=0
    check_cmd composectl "composectl" || rc=1
    if [ "${FIOCHECK_COMPOSECTL_ALIAS}" = "yes" ]; then
        check_file /usr/bin/aklite-apps l "aklite-apps -> composectl" || rc=1
    fi
    return "${rc}"
}

# FR-09: composectl reports its pinned commit
lib_composectl_cmd_version() {
    local commit="${FIOCHECK_COMPOSECTL_COMMIT:-}"
    if [ -n "${commit}" ]; then
        commit="$(printf '%s' "${commit}" | cut -c1-7)"
        check_cmd_version composectl "${commit}" "version" "${commit}" true
    else
        check_cmd_version composectl "" "version" '[0-9a-f]{7,40}'
    fi
}

# ---------------------------------------------------------------------------
# Storage — app store and compose dirs exist once apps are installed;
# /var/sota must be on the persistent /var, not inside the deployment.
# ---------------------------------------------------------------------------
lib_composectl_files_check() {
    dry_run "lib_composectl_files_check (app storage)" && return 0
    local dir n
    for dir in "${FIOCHECK_COMPOSECTL_STORE}" "${FIOCHECK_COMPOSECTL_COMPOSE}"; do
        if [ -d "$(fiocheck_path "${dir}")" ]; then
            n="$(find "$(fiocheck_path "${dir}")" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
            log_ok "App storage: ${dir} (${n} entr(y/ies))"
        elif fiocheck_registered; then
            log_warn "App storage: ${dir} missing on a registered device"
        else
            log_info "App storage: ${dir} not created yet (no app installed)"
        fi
    done
}

# FR-21: /var is the persistent stateroot var, separate from the deployment
lib_composectl_storage_persistent() {
    dry_run "lib_composectl_storage_persistent (/var mount)" && return 0
    require_runtime "/var mount" || return 0
    if [ ! -d /ostree ] && [ ! -d /sysroot/ostree ]; then
        log_skip "App storage persistence: not an ostree system"
        return 0
    fi
    if awk '$2=="/var" { found=1 } END { exit !found }' /proc/mounts 2>/dev/null; then
        log_ok "App storage persistence: /var is a separate mount (ostree stateroot var)"
        return 0
    fi
    log_fail "App storage persistence: /var is not mounted separately — apps would not survive an OS update"
    return 1
}

# ---------------------------------------------------------------------------
# Runtime — composectl talks to dockerd
# ---------------------------------------------------------------------------
lib_composectl_runtime_check() {
    dry_run "lib_composectl_runtime_check (composectl ls)" && return 0
    require_runtime "composectl ls" || return 0
    if ! command -v composectl >/dev/null 2>&1; then
        log_skip "composectl ls: composectl not installed"
        return 0
    fi
    if [ ! -S /var/run/docker.sock ]; then
        log_fail "composectl ls: docker socket missing — composectl cannot reach dockerd"
        return 1
    fi
    if composectl ls >/dev/null 2>&1; then
        log_ok "composectl ls: succeeded"
        return 0
    fi
    log_fail "composectl ls: failed"
    return 1
}

lib_composectl_all() {
    lib_composectl_cmd
    lib_composectl_cmd_version
    lib_composectl_files_check
    lib_composectl_storage_persistent
    lib_composectl_runtime_check
}
