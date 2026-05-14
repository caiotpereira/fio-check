#!/usr/bin/env sh
# =============================================================================
# lib/docker.sh — Reusable Docker and Docker Compose checks
#
# Kernel config groups derived from the official Moby check-config.sh and
# Linux microPlatform Kernel cache
#   https://github.com/moby/moby/blob/master/contrib/check-config.sh
#   https://github.com/foundriesio/lmp-kernel-cache/blob/main/features/docker/
#
# Sourced by profiles; never executed directly.
# =============================================================================

[ -n "${_LIB_DOCKER_LOADED:-}" ] && return 0
_LIB_DOCKER_LOADED=1

_DOCKER_VERSION="24.0.6"
_DOCKER_COMPOSE_VERSION="2.21.0"

lib_docker_set_version() {
    _DOCKER_VERSION="$1"
}

lib_docker_compose_set_version() {
    _DOCKER_COMPOSE_VERSION="$1"
}
# ---------------------------------------------------------------------------
# Kernel config — namespaces
# Required for container process and network isolation.
# https://github.com/foundriesio/lmp-kernel-cache/blob/main/features/namespaces/namespaces.cfg
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
# Kernel config — cgroups
# Required for resource limiting: CPU, memory, devices, I/O.
# https://github.com/foundriesio/lmp-kernel-cache/blob/main/features/cgroups/cgroups.cfg
# ---------------------------------------------------------------------------
lib_docker_kconfig_cgroups() {
    check_kconfig CONFIG_CGROUPS            # cgroup v1/v2 core
    check_kconfig CONFIG_CGROUP_FREEZER     # container pause/resume
    check_kconfig CONFIG_CPUSETS            # CPU/memory pinning
    check_kconfig CONFIG_PROC_PID_CPUSET    # Legacy support for /proc/<pid>/cpuset
    check_kconfig CONFIG_CGROUP_CPUACCT     # CPU accounting
    check_kconfig CONFIG_CGROUP_PIDS        # PID limits (docker --pids-limit)
    check_kconfig CONFIG_CGROUP_NET_PRIO    # Network priority control
    check_kconfig CONFIG_CGROUP_PERF        # Performance monitoring subsystem
    check_kconfig CONFIG_CGROUP_BPF         # BPF enablement
    check_kconfig CONFIG_CGROUP_DEVICE      # device allowed list
    check_kconfig CONFIG_CGROUP_SCHED       # CPU scheduling
    check_kconfig CONFIG_MEMCG              # memory controller
    check_kconfig CONFIG_KEYS               # kernel key retention (secrets)
    check_kconfig CONFIG_POSIX_MQUEUE       # /dev/mqueue bind-mount support
    check_kconfig CONFIG_BLK_CGROUP         # Block IO (disk) control cgroup
}

# ---------------------------------------------------------------------------
# Kernel config — networking
# Required for container networking, port mapping, and bridge networking.
# https://github.com/foundriesio/lmp-kernel-cache/blob/main/features/vxlan/vxlan.cfg
# https://github.com/foundriesio/lmp-kernel-cache/blob/main/features/netfilter/netfilter.cfg
# https://github.com/foundriesio/lmp-kernel-cache/blob/main/features/docker/docker.cfg
# ---------------------------------------------------------------------------
lib_docker_kconfig_network() {
    # Virtual ethernet pairs (veth) — one end in container, one on host
    check_kconfig CONFIG_VETH
    check_kconfig CONFIG_IPVLAN
    check_kconfig CONFIG_MACVLAN
    check_kconfig CONFIG_DUMMY
    check_kconfig CONFIG_IP_VS
    check_kconfig CONFIG_IP_VS_NFCT
    check_kconfig CONFIG_IP_VS_RR
    check_kconfig CONFIG_VXLAN      #Virtual Extensible Lan


    # Bridge networking — docker0 bridge
    check_kconfig CONFIG_BRIDGE
    check_kconfig CONFIG_BRIDGE_NETFILTER

    # iptables / nftables — NAT and port forwarding
    check_kconfig CONFIG_IP_NF_FILTER
    check_kconfig CONFIG_IP_NF_MANGLE
    check_kconfig CONFIG_IP_NF_TARGET_MASQUERADE    # MASQUERADE for outbound NAT
    check_kconfig CONFIG_IP_NF_NAT
    check_kconfig CONFIG_NF_NAT

    # Netfilter match extensions
    check_kconfig CONFIG_NETFILTER_XT_MATCH_ADDRTYPE
    check_kconfig CONFIG_NETFILTER_XT_MATCH_CONNTRACK
    check_kconfig CONFIG_NETFILTER_XT_MARK
    #Posix event queue (/dev/mqueue)
    check_kconfig CONFIG_POSIX_MQUEUE


}


# ---------------------------------------------------------------------------
# Kernel config — optional features
# Not required for basic Docker operation but needed for specific features.
# ---------------------------------------------------------------------------
lib_docker_kconfig_optional() {
    # Seccomp — syscall filtering (docker --security-opt seccomp)
    check_kconfig CONFIG_SECCOMP
    check_kconfig CONFIG_SECCOMP_FILTER

    # BPF — eBPF-based networking (used by newer Docker/containerd)
    check_kconfig CONFIG_BPF_SYSCALL

    # Overlay filesystem — default storage driver
    check_kconfig CONFIG_OVERLAY_FS

    # IP Virtual Server — required for Docker Swarm mode load balancing
    check_kconfig CONFIG_IP_VS
    check_kconfig CONFIG_IP_VS_NFCT
    check_kconfig CONFIG_IP_VS_RR

    # cgroup optional features
    check_kconfig CONFIG_BLK_CGROUP         # block I/O cgroup
    check_kconfig CONFIG_BLK_DEV_THROTTLING # I/O throttling
    check_kconfig CONFIG_FAIR_GROUP_SCHED   # fair CPU scheduling
    check_kconfig CONFIG_CFS_BANDWIDTH      # CFS CPU bandwidth control


    # # IPv6 support
    # check_kconfig CONFIG_IP6_NF_FILTER
    # check_kconfig CONFIG_IP6_NF_MANGLE
    # check_kconfig CONFIG_IP6_NF_TARGET_MASQUERADE

    #Enable auth tokens and access key in kernel
    check_kconfig CONFIG_KEYS
    check_kconfig CONFIG_DM_THIN_PROVISIONING #Device mapper

}

lib_docker_kernel_config(){
    check_sysctl net.ipv4.ip_forward 1
    # check_sysctl net.ipv6.conf.all.forwarding 1
    # check_sysctl net.ipv6.conf.default.forwarding 1
}

# ---------------------------------------------------------------------------
# Kernel config — all required (namespaces + cgroups + network)
# ---------------------------------------------------------------------------
lib_docker_kconfig_required() {
    lib_docker_kconfig_namespaces
    lib_docker_kconfig_cgroups
    lib_docker_kconfig_network
}

# ---------------------------------------------------------------------------
# Runtime — cgroup hierarchy
# Docker needs cgroups properly mounted (v1 or v2).
# ---------------------------------------------------------------------------
lib_docker_cgroup_mount() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_run "lib_docker_cgroup_mount (dry-run: system probe skipped)"
        return 0
    fi

    log_info "Checking cgroup hierarchy"

    # cgroupv2 — unified hierarchy at /sys/fs/cgroup
    if [ "$(stat -f -c %t /sys/fs/cgroup 2>/dev/null)" = "63677270" ]; then
        log_ok "cgroup hierarchy: cgroupv2 (unified)"
        local ctrl_file="/sys/fs/cgroup/cgroup.controllers"
        if [ -r "${ctrl_file}" ]; then
            for ctrl in cpu cpuset io memory pids; do
                if grep -qE "(^| )${ctrl}( |$)" "${ctrl_file}" 2>/dev/null; then
                    log_ok "  cgroup controller: ${ctrl}"
                else
                    log_warn "  cgroup controller missing: ${ctrl}"
                fi
            done
        fi
        return 0
    fi

    # cgroupv1 — check individual subsystem mounts
    local cgroup_dir
    cgroup_dir="$(awk '/[, ](cpu|cpuacct|cpuset|devices|freezer|memory)[, ]/ \
        && $3=="cgroup" { print $2; exit }' /proc/mounts 2>/dev/null || true)"

    if [ -n "${cgroup_dir}" ]; then
        log_ok "cgroup hierarchy: v1 mounted at ${cgroup_dir}"
        for subsys in cpu cpuacct cpuset devices freezer memory; do
            if [ -d "${cgroup_dir}/${subsys}" ]; then
                log_ok "  cgroup subsystem: ${subsys}"
            else
                log_warn "  cgroup subsystem missing: ${subsys}"
            fi
        done
    else
        log_fail "cgroup hierarchy: not properly mounted — Docker will not start"
    fi
}

# ---------------------------------------------------------------------------
# Commands — Docker engine
# ---------------------------------------------------------------------------
lib_docker_cmds() {
    check_cmd docker          "docker-ce / docker.io"
    check_cmd dockerd         "docker-ce / docker.io"
    check_cmd containerd      "containerd.io"
    check_cmd runc            "runc"
}

# ---------------------------------------------------------------------------
# Commands — Docker Compose
# Handles both v1 (docker-compose) and v2 (docker compose plugin).
# ---------------------------------------------------------------------------
lib_docker_compose_cmds() {
    log_info "Checking Docker Compose availability"

    # v2 plugin: docker compose (space, not dash)
    if docker compose version >/dev/null 2>&1; then
        local v2_ver; v2_ver="$(docker compose version 2>/dev/null | head -1)"
        log_ok "Docker Compose v2 plugin: ${v2_ver}"
        return 0
    fi

    # v1 standalone: docker-compose
    if command -v docker-compose >/dev/null 2>&1; then
        local v1_ver; v1_ver="$(docker-compose --version 2>/dev/null | head -1)"
        log_ok "Docker Compose v1 standalone: ${v1_ver}"
        log_warn "Docker Compose v1 is deprecated — consider upgrading to v2 plugin"
        return 0
    fi

    log_fail "Docker Compose not found (neither 'docker compose' plugin nor 'docker-compose')"
    return 1
}

# ---------------------------------------------------------------------------
# Functional — Docker daemon running and responsive
# ---------------------------------------------------------------------------
lib_docker_daemon() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        print_dryrun "lib_docker_daemon (dry-run: system probe skipped)"
        return 0
    fi

    log_info "Checking Docker daemon"

    if docker info >/dev/null 2>&1; then
        log_ok "Docker daemon: running and responsive"

        # Surface key daemon info
        local storage_driver; storage_driver="$(docker info --format '{{.Driver}}' 2>/dev/null || true)"
        local cgroup_driver;  cgroup_driver="$(docker info --format '{{.CgroupDriver}}' 2>/dev/null || true)"
        local server_ver;     server_ver="$(docker info --format '{{.ServerVersion}}' 2>/dev/null || true)"

        [ -n "${server_ver}"     ] && log_info "  Docker server version: ${server_ver}"
        [ -n "${storage_driver}" ] && log_info "  Storage driver: ${storage_driver}"
        [ -n "${cgroup_driver}"  ] && log_info "  Cgroup driver: ${cgroup_driver}"

        # Warn if using deprecated storage driver
        case "${storage_driver}" in
            devicemapper|aufs)
                log_warn "  Storage driver '${storage_driver}' is deprecated — use overlay2" ;;
        esac
    else
        log_fail "Docker daemon: not running or not accessible (try: systemctl start docker)"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Functional — Docker Compose version and plugin health
# ---------------------------------------------------------------------------
lib_docker_compose_version() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_run "lib_docker_compose_version (dry-run: system probe skipped)"
        return 0
    fi

    log_info "Checking Docker Compose version"

    if docker compose version >/dev/null 2>&1; then
        local ver; ver="$(docker compose version 2>/dev/null)"
        log_ok "Docker Compose: ${ver}"
    elif command -v docker-compose >/dev/null 2>&1; then
        local ver; ver="$(docker-compose --version 2>/dev/null)"
        log_ok "Docker Compose v1: ${ver}"
    else
        log_fail "Docker Compose version check failed: not installed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Functional — Docker and Docker API version
# ---------------------------------------------------------------------------
lib_docker_version() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_run "docker version check"
        _dry_run "docker info summary"
    else
        if command -v docker >/dev/null 2>&1; then
            local cli_ver; cli_ver="$(docker version --format '{{.Client.Version}}' 2>/dev/null || true)"
            local api_ver; api_ver="$(docker version --format '{{.Client.APIVersion}}' 2>/dev/null || true)"

            if [ -n "${cli_ver}" ]; then
                log_ok "Docker CLI version: ${cli_ver} (API ${api_ver})"
            else
                log_warn "Docker CLI found but 'docker version' failed — daemon may be down"
            fi
        else
            log_skip "Docker info: docker CLI not available"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Functional — Docker Socket Status
# ---------------------------------------------------------------------------
lib_docker_socket(){
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_run "Docker socket presence and permissions check"
    else
        log_info "Checking Docker socket"
        if [ -S /var/run/docker.sock ]; then
            log_ok "Docker socket: /var/run/docker.sock present"
            # Check if current user can access it (without sudo)
            if [ -r /var/run/docker.sock ] && [ -w /var/run/docker.sock ]; then
                log_ok "Docker socket: accessible by current user ($(id -un))"
            else
                local sock_group; sock_group="$(stat -c '%G' /var/run/docker.sock 2>/dev/null || true)"
                log_warn "Docker socket: not accessible without sudo — add user to '${sock_group:-docker}' group"
                log_info "  Fix: sudo usermod -aG ${sock_group:-docker} \$(whoami) && newgrp ${sock_group:-docker}"
            fi
        else
            log_fail "Docker socket not found at /var/run/docker.sock — is Docker running?"
            return 1
        fi
    fi
}



# ---------------------------------------------------------------------------
# Functional — pull and run hello-world container (live smoke test)
# Only runs when TESTFW_DOCKER_SMOKE=1 is set to avoid unwanted network calls.
# ---------------------------------------------------------------------------
lib_docker_smoke_test() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_docker_smoke_test (dry-run: system probe skipped)"
        return 0
    fi

    if [ "${FIOCHECK_DOCKER_SMOKE:-0}" -ne 1 ]; then
        log_skip "Docker smoke test (set TESTFW_DOCKER_SMOKE=1 to enable)"
        return 0
    fi

    log_info "Running Docker hello-world smoke test"
    if docker run --rm hello-world >/dev/null 2>&1; then
        log_ok "Docker smoke test: hello-world container ran successfully"
        docker rmi hello-world >/dev/null 2>&1 || true
    else
        log_fail "Docker smoke test: hello-world container failed"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# lib_docker_all — full Docker check suite (required configs + runtime)
# lib_docker_compose_all — full Docker Compose check suite
# ---------------------------------------------------------------------------
lib_docker_all() {
    lib_docker_kconfig_required
    lib_docker_cgroup_mount
    lib_docker_cmds
    lib_docker_daemon
}

lib_docker_compose_all() {
    lib_docker_compose_cmds
    lib_docker_compose_version
}
