#!/usr/bin/env sh
# =============================================================================
# Profile  : docker
# Purpose  : Validate Docker Engine and Docker Compose installation,
#            kernel requirements, and runtime health.
#
# Kernel config groups (from Moby check-config.sh):
#   Required  — namespaces, cgroups, bridge networking, iptables/NAT
#
# Environment variables
#   FIOCHECK_DOCKER_SMOKE=1   enable live hello-world smoke test (pulls from
#                           registry — disabled by default for offline targets)
#
# Usage
#   ./basename $0 load docker
#   ./basename $0 --dry-run load docker
#   ./basename $0 --filter fail load docker
#   FIOCHECK_DOCKER_SMOKE=1 ./basename $0 -r /tmp/docker_report.txt load docker
# =============================================================================

source "${FIO_TEST_LIB}/lib_docker.sh"

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------

fiocheck_pre_hook() {
    _DOCKER_PROFILE_TS="$(date +%s)"
    log_info "pre_hook: Docker validation started at $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "pre_hook: kernel $(uname -r) / arch $(uname -m)"

    if [[ "${FIOCHECK_DOCKER_SMOKE:-0}" -eq 1 ]]; then
        log_info "pre_hook: smoke test enabled (FIOCHECK_DOCKER_SMOKE=1)"
    else
        log_info "pre_hook: smoke test disabled (export FIOCHECK_DOCKER_SMOKE=1 to enable)"
    fi
}

fiocheck_post_hook() {
    local elapsed=$(( $(date +%s) - ${_DOCKER_PROFILE_TS:-0} ))
    log_info "post_hook: Docker validation completed in ${elapsed}s"
}

# ---------------------------------------------------------------------------
# 1. Kernel config — required
#    These must all be enabled (y or m) or Docker will not start.
# ---------------------------------------------------------------------------

print_section "Kernel — Namespaces"
lib_docker_kconfig_namespaces

print_section "Kernel — Cgroups"
lib_docker_kconfig_cgroups

print_section "Kernel — Networking"
lib_docker_kconfig_network

print_section "Kernel - Optional Configurations"
lib_docker_kconfig_optional

# ---------------------------------------------------------------------------
# 3. Cgroup hierarchy runtime check
#    Verifies cgroupv2 (unified) or cgroupv1 subsystems are mounted.
# ---------------------------------------------------------------------------

print_section "Cgroup Hierarchy"
lib_docker_cgroup_mount

# ---------------------------------------------------------------------------
# 4. Docker Engine — binaries and daemon
# ---------------------------------------------------------------------------

print_section "Docker Engine — Binaries"
lib_docker_cmds

print_section "Docker Engine — Daemon"
lib_docker_daemon

# ---------------------------------------------------------------------------
# 5. Docker Compose
# ---------------------------------------------------------------------------

print_section "Docker Compose"
lib_docker_compose_cmds

# ---------------------------------------------------------------------------
# 6. Docker socket and permissions
# ---------------------------------------------------------------------------

print_section "Docker Socket info"
lib_docker_socket
# ---------------------------------------------------------------------------
# 7. Docker info summary
# ---------------------------------------------------------------------------
print_section "Docker/Compose/API Version"
lib_docker_compose_version
lib_docker_version



# ---------------------------------------------------------------------------
# 8. Optional live smoke test
#    Disabled by default. Enable with: export FIOCHECK_DOCKER_SMOKE=1
# ---------------------------------------------------------------------------

print_section "Smoke Test"
lib_docker_smoke_test