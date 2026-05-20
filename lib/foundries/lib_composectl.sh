#!/usr/bin/env sh
# =============================================================================
# lib/foundries/lib_composectl.sh — Foundries.io Compose App manager (composectl)
#
# composectl is a statically linked Go CLI tool that manages Compose Apps
# on LmP devices. It replaced skopeo for app management in LmP v93+.
# aktualizr-lite invokes it directly — composectl has no daemon or service.
#
# Architecture
#   Binary        : /usr/bin/composectl  (statically linked Go, no .so deps)
#   App store     : /var/sota/reset-apps/<app>/   (restorable — default LmP v85+)
#                   /var/sota/compose-apps/<app>/  (legacy compose type)
#   Docker store  : /var/lib/docker               (managed by Docker daemon)
#   Docker socket : /var/run/docker.sock          (composectl <-> dockerd IPC)
#   App DB        : bbolt embedded in the store dir (no external DB process)
#
# Key commands
#   composectl ls                    list installed apps
#   composectl pull <uri>            fetch app blobs from registry
#   composectl install <uri>         install/update an app
#   composectl run <uri>             start app containers via Docker
#   composectl status                show running app status
#   composectl --store/-s <dir>      override app store directory
#   composectl --compose/-i <dir>    override compose project directory
#
# References
#   https://github.com/foundriesio/composeapp
#   https://docs.foundries.io/latest/user-guide/containers-and-docker/compose-apps.html
#   https://docs.foundries.io/latest/reference-manual/linux/linux-lmp-fs.html
#
# Sourced by profiles; never executed directly.
# =============================================================================

[ -n "${_LIB_COMPOSECTL_LOADED:-}" ] && return 0
_LIB_COMPOSECTL_LOADED=1

# ---------------------------------------------------------------------------
# lib_composectl_kconfig — kernel requirements
#
# composectl itself only needs a working filesystem and network stack, but
# the Docker daemon it communicates with needs the full container kernel
# stack.  These are the configs that must be present for compose apps to
# run correctly on the device.
# ---------------------------------------------------------------------------
lib_composectl_kconfig() {
    # ── Namespaces — container isolation ────────────────────────────────────
    check_kconfig CONFIG_NAMESPACES
    check_kconfig CONFIG_NET_NS             # network namespace per container
    check_kconfig CONFIG_PID_NS             # PID namespace
    check_kconfig CONFIG_IPC_NS             # IPC namespace
    check_kconfig CONFIG_UTS_NS             # hostname namespace
    check_kconfig CONFIG_USER_NS            # user namespace (rootless)

    # ── Cgroups — resource control ──────────────────────────────────────────
    check_kconfig CONFIG_CGROUPS
    check_kconfig CONFIG_CGROUP_DEVICE      # device whitelist per container
    check_kconfig CONFIG_MEMCG              # memory limiting
    check_kconfig CONFIG_CGROUP_PIDS        # PID limits

    # ── Storage driver — overlay2 ────────────────────────────────────────────
    # composectl and Docker use overlay2 as the storage driver on LmP.
    # This is required — without it Docker falls back to vfs (very slow).
    check_kconfig CONFIG_OVERLAY_FS

    # ── Container networking ─────────────────────────────────────────────────
    check_kconfig CONFIG_VETH               # virtual ethernet pairs
    check_kconfig CONFIG_BRIDGE             # docker0 bridge
    check_kconfig CONFIG_NET
    check_kconfig CONFIG_INET

    # ── Unix domain sockets — docker.sock ────────────────────────────────────
    check_kconfig CONFIG_UNIX
}

# ---------------------------------------------------------------------------
# lib_composectl_lib_check — shared library dependencies
#
# composectl is statically linked Go — it has no .so runtime dependencies
# of its own.  The checks here cover the Docker daemon and containerd
# runtime that composectl orchestrates, which do have C library deps.
# ---------------------------------------------------------------------------
lib_composectl_lib_check() {
    # libseccomp — Docker/containerd syscall filtering
    check_lib_dependency seccomp "libseccomp / libseccomp-dev"

    # libdevmapper — device-mapper storage backend (used by containerd)
    # warn-only: not needed when overlay2 is the only storage driver
    if check_lib_dependency devmapper "lvm2" 2>/dev/null; then
        log_ok "Library: libdevmapper (device-mapper storage support)"
    else
        log_warn "Library: libdevmapper not found — device-mapper storage unavailable (overlay2 still works)"
    fi
}

# ---------------------------------------------------------------------------
# lib_composectl_cmd — binary and tooling checks
# ---------------------------------------------------------------------------
lib_composectl_cmd() {
    # composectl itself
    check_cmd composectl "composeapp (meta-lmp / Foundries.io LmP image)"

    # Docker daemon — composectl communicates with it via docker.sock
    check_cmd dockerd    "docker-ce / docker.io"
    check_cmd docker     "docker-ce / docker.io"

    # containerd — container runtime invoked by Docker
    check_cmd containerd "containerd.io"

    # runc — OCI container runtime
    check_cmd runc       "runc"
}

# ---------------------------------------------------------------------------
# lib_composectl_cmd_version — check composectl version (optional)
#
# composectl uses semver; pass a minimum version to enforce it.
# Example: lib_composectl_cmd_version "0.1.0"
# ---------------------------------------------------------------------------
lib_composectl_cmd_version() {
    local min_ver="${1:-0.0.0}"
    check_cmd_version "composectl" "${min_ver}" "version" \
        '[0-9]+\.[0-9]+\.[0-9]+'
}

# ---------------------------------------------------------------------------
# lib_composectl_files_check — runtime paths and storage layout
# ---------------------------------------------------------------------------
lib_composectl_files_check() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_composectl_files_check (dry-run: filesystem probes skipped)"
        return 0
    fi

    # ── Docker socket ────────────────────────────────────────────────────────
    log_info "Checking Docker socket: /var/run/docker.sock"
    if [ -S /var/run/docker.sock ]; then
        log_ok "Docker socket: /var/run/docker.sock present"
    else
        log_fail "Docker socket not found: /var/run/docker.sock — composectl cannot communicate with Docker"
        return 1
    fi

    # ── App store — restorable apps (default since LmP v85) ─────────────────
    local reset_apps_dir="/var/sota/reset-apps"
    log_info "Checking restorable app store: ${reset_apps_dir}"
    if [ -d "${reset_apps_dir}" ]; then
        local app_count
        app_count="$(find "${reset_apps_dir}" -mindepth 1 -maxdepth 1 \
            -type d 2>/dev/null | wc -l)"
        log_ok "Restorable app store: ${reset_apps_dir} (${app_count} app(s))"
        # List app names if any are present
        if [ "${app_count}" -gt 0 ]; then
            find "${reset_apps_dir}" -mindepth 1 -maxdepth 1 -type d \
                2>/dev/null | sed 's|.*/||' | sort \
                | while IFS= read -r app; do
                    log_info "  app: ${app}"
                done
        fi
    else
        log_warn "Restorable app store not found: ${reset_apps_dir} — /var/sota not populated yet"
    fi

    # ── App store — legacy compose type ─────────────────────────────────────
    local compose_apps_dir="/var/sota/compose-apps"
    log_info "Checking compose app store: ${compose_apps_dir}"
    if [ -d "${compose_apps_dir}" ]; then
        local compose_count
        compose_count="$(find "${compose_apps_dir}" -mindepth 1 -maxdepth 1 \
            -type d 2>/dev/null | wc -l)"
        log_ok "Compose app store: ${compose_apps_dir} (${compose_count} app(s))"
        if [ "${compose_count}" -gt 0 ]; then
            find "${compose_apps_dir}" -mindepth 1 -maxdepth 1 -type d \
                2>/dev/null | sed 's|.*/||' | sort \
                | while IFS= read -r app; do
                    # Check that each app directory has a docker-compose.yml
                    if [ -f "${compose_apps_dir}/${app}/docker-compose.yml" ]; then
                        log_ok  "  app: ${app} (docker-compose.yml present)"
                    else
                        log_warn "  app: ${app} (docker-compose.yml missing)"
                    fi
                done
        fi
    else
        log_warn "Compose app store not found: ${compose_apps_dir} — /var/sota not populated yet"
    fi

    # ── Docker engine store ──────────────────────────────────────────────────
    local docker_store="/var/lib/docker"
    log_info "Checking Docker engine store: ${docker_store}"
    if [ -d "${docker_store}" ]; then
        # Check overlay2 subdirectory is present (indicates overlay2 driver in use)
        if [ -d "${docker_store}/overlay2" ]; then
            log_ok "Docker store: ${docker_store} (overlay2 driver active)"
        else
            log_warn "Docker store: ${docker_store} present but overlay2 subdir missing — check storage driver"
        fi
    else
        log_warn "Docker store not found: ${docker_store} — Docker may not have started yet"
    fi

    # ── sota.toml app configuration ──────────────────────────────────────────
    local sota_toml="/var/sota/sota.toml"
    log_info "Checking compose apps configuration in sota.toml"
    if [ -f "${sota_toml}" ]; then
        # Surface the apps list from the [pacman] section
        local apps_list
        apps_list="$(grep -E '^\s*compose_apps\s*=' "${sota_toml}" 2>/dev/null \
            | head -1 | cut -d= -f2- | tr -d '"' | xargs || true)"
        if [ -n "${apps_list}" ]; then
            log_ok "Configured apps in sota.toml: ${apps_list}"
        else
            log_info "No compose_apps list in sota.toml (all apps enabled or not yet configured)"
        fi

        # Surface app type (restorable vs compose)
        local app_type
        app_type="$(grep -E '^\s*type\s*=' "${sota_toml}" 2>/dev/null \
            | head -1 | cut -d= -f2 | tr -d '" ' || true)"
        [ -n "${app_type}" ] && log_info "App type in sota.toml: ${app_type}"
    else
        log_warn "sota.toml not found: ${sota_toml} — /var/sota not populated yet"
    fi
}

# ---------------------------------------------------------------------------
# lib_composectl_runtime_check — functional checks against live Docker daemon
# ---------------------------------------------------------------------------
lib_composectl_runtime_check() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_composectl_runtime_check (dry-run: system probe skipped)"
        return 0
    fi

    log_info "Checking composectl runtime"

    if ! command -v composectl >/dev/null 2>&1; then
        log_skip "composectl runtime check: binary not available"
        return 0
    fi

    if [ ! -S /var/run/docker.sock ]; then
        log_skip "composectl runtime check: docker.sock not available"
        return 0
    fi

    # composectl ls — non-destructive, lists installed apps
    local ls_output
    if ls_output="$(composectl ls 2>/dev/null)"; then
        local installed_count
        installed_count="$(printf '%s\n' "${ls_output}" | grep -c '.' || true)"
        log_ok "composectl ls: succeeded (${installed_count} app(s) listed)"
    else
        log_warn "composectl ls failed — Docker daemon may not be running or store is empty"
    fi
}

# ---------------------------------------------------------------------------
# lib_composectl_all — full composectl check suite
# ---------------------------------------------------------------------------
lib_composectl_all() {
    lib_composectl_kconfig
    lib_composectl_lib_check
    lib_composectl_cmd
    lib_composectl_files_check
    lib_composectl_runtime_check
}
