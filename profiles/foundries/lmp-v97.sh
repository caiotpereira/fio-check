#!/usr/bin/env sh
# =============================================================================
# Profile  : lmp-v97
# Purpose  : Validate the requires tools to execute OTA in LmP v97
#
# Kernel config groups (from Moby check-config.sh):
#   Required  — namespaces, cgroups, bridge networking, iptables/NAT
#   Optional  — overlay2 storage, seccomp, BPF, IPv6, Swarm (IP_VS)
#
# Environment variables
#   TESTFW_DOCKER_SMOKE=1   enable live hello-world smoke test (pulls from
#                           registry — disabled by default for offline targets)
#
# Usage
#   ./basename $0 load lmp-v97
#   ./basename $0 --dry-run load lmp-v97
#   ./basename $0 --filter fail load lmp-v97
#   FIO_TEST_LMP_SECURE=1 ./basename $0 -r /tmp/docker_report.txt load lmp-v97
# =============================================================================

source "${FIO_TEST_LIB}/foundries/lib_aktualizr.sh"
source "${FIO_TEST_LIB}/foundries/lib_lib_compose_apps_early_start_all.sh"
aource "${FIO_TEST_LIB}/foundries/lib_fioconfig.sh"
source "${FIO_TEST_LIB}/foundries/lib_composectl.sh"
source "${FIO_TEST_LIB}/foundries/lib_fiovb.sh"
source "${FIO_TEST_LIB}/foundries/lib_lmp_device_register.sh"

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------
_LMP_VERSION=97
_AKLITE_VERSION="067a72f"
testfw_pre_hook() {
    _LMP_PROFILE_TS="$(date +%s)"
    log_info "pre_hook: LmP validation started at $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "pre_hook: kernel $(uname -r) / arch $(uname -m)"

    if [[ "${FIO_TEST_LMP_SECURE:-0}" -eq 1 ]]; then
        log_info "pre_hook: LmP ${_LMP_VERSION} Secure test enabled (FIO_TEST_LMP_SECURE=1)"
    else
        log_info "pre_hook: LmP ${_LMP_VERSION} Secure test disabled (export FIO_TEST_LMP_SECURE=1 to enable)"
    fi
}

testfw_post_hook() {
    local elapsed=$(( $(date +%s) - ${_LMP_PROFILE_TS:-0} ))
    log_info "post_hook: LmP ${_LMP_VERSION} validation completed in ${elapsed}s"
}

# 1 - Aktualizr-lite version check
print_section "Verify Aktualizr-lite"
lib_aktualizr_set_version "${_AKLITE_VERSION}"
lib_aktualizr_cmd

print_section "Verify compose_apps_early_start"
lib_compose_apps_early_start_all

print_section "Verify Fioconfig"
lib_fioconfig_all

print_section "Verify Composectl"
lib_composectl_all

print_section "Verify optee-fiovb"
if [[ "$(uname -m)" == "aarch64" ]]; then
    lib_fiovb_all
else
    log_skip "optee-fiovb: skipped — requires aarch64 (detected: $(uname -m))"
fi

print_section "Verify lmp-device-register"
lib_lmp_device_register_all