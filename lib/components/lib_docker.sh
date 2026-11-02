#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_docker.sh — Docker engine and Docker Compose
#
# Kernel config groups follow the Moby check-config.sh and the LmP kernel cache:
#   https://github.com/moby/moby/blob/master/contrib/check-config.sh
#   https://github.com/foundriesio/lmp-kernel-cache/tree/main/features
#
# Expectations (set by a profile, --expect, --machine or the environment)
#   FIOCHECK_DOCKER_VERSION          minimum docker version (empty: report only)
#   FIOCHECK_DOCKER_COMPOSE_VERSION  minimum compose version (empty: report only)
#   FIOCHECK_DOCKER_STORAGE_DRIVER   expected storage driver (empty: report only)
#   FIOCHECK_DOCKER_DAEMON_JSON      daemon config file to check (empty: skip)
#   FIOCHECK_DOCKER_DAEMON_CONFIG    "key=value ..." entries the file must hold
#   FIOCHECK_DOCKER_UNIT_STATE       docker.service enable state (empty: any)
#   FIOCHECK_DOCKER_SMOKE            1: pull and run hello-world (network)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_DOCKER_LOADED:-}" ] && return 0
_LIB_DOCKER_LOADED=1

_DOCKER_SOCKET="/var/run/docker.sock"
_DOCKER_COMPOSE_PLUGINS="/usr/libexec/docker/cli-plugins/docker-compose \
/usr/lib/docker/cli-plugins/docker-compose \
/usr/local/lib/docker/cli-plugins/docker-compose"

# Kept for profiles written before the FIOCHECK_* variables
lib_docker_set_version()         { FIOCHECK_DOCKER_VERSION="$1"; }
lib_docker_compose_set_version() { FIOCHECK_DOCKER_COMPOSE_VERSION="$1"; }

# ---------------------------------------------------------------------------
# Kernel config — namespaces (container isolation)
# ---------------------------------------------------------------------------
lib_docker_kconfig_namespaces() {
    check_kconfig CONFIG_NAMESPACES         # namespace subsystem
    check_kconfig CONFIG_UTS_NS             # UTS (hostname) namespace
    check_kconfig CONFIG_IPC_NS             # IPC namespace
    check_kconfig CONFIG_USER_NS            # user namespace (rootless Docker)
    check_kconfig CONFIG_PID_NS             # PID namespace
    check_kconfig CONFIG_NET_NS             # network namespace
}

# ---------------------------------------------------------------------------
# Kernel config — cgroups (resource limits)
# ---------------------------------------------------------------------------
lib_docker_kconfig_cgroups() {
    check_kconfig CONFIG_CGROUPS            # cgroup v1/v2 core
    check_kconfig CONFIG_CGROUP_FREEZER     # container pause/resume
    check_kconfig CONFIG_CPUSETS            # CPU/memory pinning
    check_kconfig CONFIG_CGROUP_CPUACCT     # CPU accounting
    check_kconfig CONFIG_CGROUP_PIDS        # PID limits (docker --pids-limit)
    check_kconfig CONFIG_CGROUP_DEVICE      # device allow list
    check_kconfig CONFIG_CGROUP_SCHED       # CPU scheduling
    check_kconfig CONFIG_MEMCG              # memory controller
    check_kconfig CONFIG_BLK_CGROUP         # block I/O controller
    check_kconfig CONFIG_KEYS               # kernel key retention
    check_kconfig CONFIG_POSIX_MQUEUE       # /dev/mqueue
}

# ---------------------------------------------------------------------------
# Kernel config — networking (bridge, NAT, port mapping)
# ---------------------------------------------------------------------------
lib_docker_kconfig_network() {
    check_kconfig CONFIG_VETH                           # container veth pairs
    check_kconfig CONFIG_BRIDGE                         # docker0 bridge
    check_kconfig CONFIG_BRIDGE_NETFILTER
    check_kconfig CONFIG_IP_NF_FILTER
    check_kconfig CONFIG_IP_NF_MANGLE
    check_kconfig CONFIG_IP_NF_TARGET_MASQUERADE        # outbound NAT
    check_kconfig CONFIG_IP_NF_NAT
    check_kconfig CONFIG_NF_NAT
    check_kconfig CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
    check_kconfig CONFIG_NETFILTER_XT_MATCH_CONNTRACK
    check_kconfig CONFIG_NETFILTER_XT_MARK
}

# ---------------------------------------------------------------------------
# Kernel config — storage and optional features
# ---------------------------------------------------------------------------
lib_docker_kconfig_optional() {
    check_kconfig CONFIG_OVERLAY_FS         # overlay2 storage driver
    check_kconfig CONFIG_SECCOMP            # syscall filtering
    check_kconfig CONFIG_SECCOMP_FILTER
    check_kconfig CONFIG_BPF_SYSCALL        # cgroup v2 device control
    check_kconfig CONFIG_CGROUP_BPF
    check_kconfig CONFIG_VXLAN              # overlay networks
    check_kconfig CONFIG_IPVLAN
    check_kconfig CONFIG_MACVLAN
    check_kconfig CONFIG_DUMMY
    check_kconfig CONFIG_BLK_DEV_THROTTLING # I/O throttling
    check_kconfig CONFIG_CFS_BANDWIDTH      # CPU quota
}

lib_docker_kconfig_required() {
    lib_docker_kconfig_namespaces
    lib_docker_kconfig_cgroups
    lib_docker_kconfig_network
}

# IPv4 forwarding is required for container networking
lib_docker_kernel_config() {
    check_sysctl net.ipv4.ip_forward 1
}

# ---------------------------------------------------------------------------
# Runtime — cgroup hierarchy mounted (v2 unified or v1 controllers)
# ---------------------------------------------------------------------------
lib_docker_cgroup_mount() {
    dry_run "lib_docker_cgroup_mount (cgroup hierarchy probe)" && return 0
    require_runtime "cgroup hierarchy" || return 0

    if [ "$(stat -f -c %t /sys/fs/cgroup 2>/dev/null)" = "63677270" ]; then
        log_ok "cgroup hierarchy: cgroupv2 (unified)"
        local ctrl
        for ctrl in cpu cpuset io memory pids; do
            if grep -qE "(^| )${ctrl}( |$)" /sys/fs/cgroup/cgroup.controllers 2>/dev/null; then
                log_ok "  cgroup controller: ${ctrl}"
            else
                log_warn "  cgroup controller missing: ${ctrl}"
            fi
        done
        return 0
    fi

    local dir
    dir="$(awk '$3=="cgroup" && $4 ~ /(^|,)memory(,|$)/ { print $2; exit }' /proc/mounts 2>/dev/null)"
    if [ -n "${dir}" ]; then
        log_ok "cgroup hierarchy: v1 (memory controller at ${dir})"
        return 0
    fi
    log_fail "cgroup hierarchy: not mounted — Docker will not start"
    return 1
}

# ---------------------------------------------------------------------------
# Commands — engine
# ---------------------------------------------------------------------------
lib_docker_cmds() {
    local rc=0
    check_cmd docker     "docker-moby" || rc=1
    check_cmd dockerd    "docker-moby" || rc=1
    check_cmd containerd "containerd"  || rc=1
    check_cmd runc       "runc"        || rc=1
    return "${rc}"
}

# ---------------------------------------------------------------------------
# Commands — Docker Compose v2 plugin (or the standalone docker-compose)
# ---------------------------------------------------------------------------
lib_docker_compose_cmds() {
    dry_run "lib_docker_compose_cmds (compose plugin probe)" && return 0
    local p
    for p in ${_DOCKER_COMPOSE_PLUGINS}; do
        if [ -e "$(fiocheck_path "${p}")" ]; then
            log_ok "Docker Compose v2 plugin: ${p}"
            return 0
        fi
    done
    if [ -n "$(_find_cmd docker-compose)" ]; then
        log_ok "Docker Compose standalone: docker-compose"
        return 0
    fi
    log_fail "Docker Compose not found (no cli-plugins/docker-compose, no docker-compose)"
    return 1
}

# ---------------------------------------------------------------------------
# Unit — docker.service present, not masked
# ---------------------------------------------------------------------------
lib_docker_service() {
    check_systemd_unit docker.service "${FIOCHECK_DOCKER_UNIT_STATE:-}"
}

# ---------------------------------------------------------------------------
# Config — daemon.json entries (static)
# ---------------------------------------------------------------------------
lib_docker_daemon_config() {
    if [ -z "${FIOCHECK_DOCKER_DAEMON_JSON:-}" ]; then
        log_skip "Docker daemon config: no FIOCHECK_DOCKER_DAEMON_JSON expectation"
        return 0
    fi
    check_file "${FIOCHECK_DOCKER_DAEMON_JSON}" f || return 1
    [ -n "${FIOCHECK_DOCKER_DAEMON_CONFIG:-}" ] || return 0
    # shellcheck disable=SC2086
    check_json_values "${FIOCHECK_DOCKER_DAEMON_JSON}" ${FIOCHECK_DOCKER_DAEMON_CONFIG}
}

# ---------------------------------------------------------------------------
# Runtime — daemon responsive; storage driver
# ---------------------------------------------------------------------------
lib_docker_daemon() {
    dry_run "lib_docker_daemon (docker info)" && return 0
    require_runtime "docker daemon" || return 0

    if ! docker info >/dev/null 2>&1; then
        log_fail "Docker daemon: not running or not accessible (systemctl start docker)"
        return 1
    fi
    log_ok "Docker daemon: running and responsive"
    local driver cgroup server
    driver="$(docker info --format '{{.Driver}}' 2>/dev/null)"
    cgroup="$(docker info --format '{{.CgroupDriver}}' 2>/dev/null)"
    server="$(docker info --format '{{.ServerVersion}}' 2>/dev/null)"
    [ -n "${server}" ] && log_info "  Docker server version: ${server}"
    [ -n "${cgroup}" ] && log_info "  Cgroup driver: ${cgroup}"

    local expected="${FIOCHECK_DOCKER_STORAGE_DRIVER:-}"
    if [ -n "${expected}" ]; then
        if [ "${driver}" = "${expected}" ]; then
            log_ok "Docker storage driver: ${driver}"
        else
            log_fail "Docker storage driver: ${driver:-unknown} — expected ${expected}"
            return 1
        fi
    else
        log_info "  Storage driver: ${driver}"
        case "${driver}" in
            devicemapper|aufs) log_warn "Docker storage driver '${driver}' is deprecated — use overlay2" ;;
        esac
    fi
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------
lib_docker_version() {
    check_cmd_version docker "${FIOCHECK_DOCKER_VERSION:-}"
}

lib_docker_compose_version() {
    dry_run "lib_docker_compose_version" && return 0
    if ! fiocheck_static && command -v docker >/dev/null 2>&1 \
            && docker compose version >/dev/null 2>&1; then
        check_cmd_version docker "${FIOCHECK_DOCKER_COMPOSE_VERSION:-}" "compose version"
    elif [ -n "$(_find_cmd docker-compose)" ]; then
        check_cmd_version docker-compose "${FIOCHECK_DOCKER_COMPOSE_VERSION:-}"
    else
        require_runtime "docker compose version" || return 0
        log_fail "Docker Compose version: compose not installed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Runtime — socket present and accessible by the current user
# ---------------------------------------------------------------------------
lib_docker_socket() {
    dry_run "lib_docker_socket (${_DOCKER_SOCKET})" && return 0
    require_runtime "docker socket" || return 0
    if [ ! -S "${_DOCKER_SOCKET}" ]; then
        log_fail "Docker socket not found: ${_DOCKER_SOCKET} — is Docker running?"
        return 1
    fi
    log_ok "Docker socket: ${_DOCKER_SOCKET}"
    if [ -r "${_DOCKER_SOCKET}" ] && [ -w "${_DOCKER_SOCKET}" ]; then
        log_ok "Docker socket: accessible by $(id -un)"
    else
        local grp; grp="$(stat -c '%G' "${_DOCKER_SOCKET}" 2>/dev/null)"
        log_warn "Docker socket: not accessible by $(id -un) — add the user to '${grp:-docker}'"
    fi
}

# ---------------------------------------------------------------------------
# Runtime — hello-world (opt-in: pulls from a registry)
# ---------------------------------------------------------------------------
lib_docker_smoke_test() {
    dry_run "lib_docker_smoke_test (docker run hello-world)" && return 0
    if [ "${FIOCHECK_DOCKER_SMOKE:-0}" != "1" ]; then
        log_skip "Docker smoke test (set FIOCHECK_DOCKER_SMOKE=1 to enable)"
        return 0
    fi
    require_runtime "docker smoke test" || return 0
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_ok "Docker smoke test: hello-world ran"
        docker rmi hello-world >/dev/null 2>&1 || true
        return 0
    fi
    log_fail "Docker smoke test: hello-world failed"
    return 1
}

# ---------------------------------------------------------------------------
# Suites
# ---------------------------------------------------------------------------
lib_docker_all() {
    lib_docker_kconfig_required
    lib_docker_cgroup_mount
    lib_docker_cmds
    lib_docker_service
    lib_docker_daemon_config
    lib_docker_daemon
    lib_docker_version
}

lib_docker_compose_all() {
    lib_docker_compose_cmds
    lib_docker_compose_version
}
