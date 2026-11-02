#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_fiovb.sh — Foundries.io verified boot variables (optee-fiovb)
#
# meta-lmp only, U-Boot + OP-TEE machines (meta-foundries: SR-01 descoped).
# fiovb stores the OTA boot variables (bootcount, upgrade_available, rollback)
# in RPMB through an OP-TEE trusted application. The optee-fiovb recipe installs:
#   /usr/bin/fiovb                         host client
#   /usr/bin/fiovb_{printenv,setenv,delenv} symlinks (argv[0] dispatch)
#   /lib/optee_armtz/*.ta                  trusted application
# The client reaches OP-TEE through libteec, /dev/tee0 and tee-supplicant.
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_FIOVB_LOADED:-}" ] && return 0
_LIB_FIOVB_LOADED=1

lib_fiovb_kconfig() {
    check_kconfig CONFIG_TEE
    check_kconfig CONFIG_OPTEE
    check_kconfig CONFIG_MMC_BLOCK      # /dev/mmcblkXrpmb
}

lib_fiovb_lib_check() {
    check_lib_dependency teec
}

lib_fiovb_cmd() {
    local rc=0 c
    for c in fiovb fiovb_printenv fiovb_setenv fiovb_delenv; do
        check_cmd "${c}" "optee-fiovb" || rc=1
    done
    check_cmd tee-supplicant "optee-client" || rc=1
    dry_run "fiovb trusted application" && return "${rc}"
    if [ -n "$(find "$(fiocheck_path /lib/optee_armtz)" "$(fiocheck_path /usr/lib/optee_armtz)" \
            -maxdepth 1 -name '*.ta' 2>/dev/null | head -n 1)" ]; then
        log_ok "fiovb trusted application: installed in optee_armtz"
    else
        log_fail "fiovb trusted application: no *.ta in /lib/optee_armtz"
        rc=1
    fi
    return "${rc}"
}

lib_fiovb_devices() {
    dry_run "lib_fiovb_devices (/dev/tee0, RPMB)" && return 0
    require_runtime "TEE device nodes" || return 0
    if [ ! -c /dev/tee0 ]; then
        log_fail "/dev/tee0 not found — OP-TEE driver not loaded"
        return 1
    fi
    log_ok "TEE device: /dev/tee0"
    if [ -c /dev/teepriv0 ]; then
        log_ok "TEE device: /dev/teepriv0 (tee-supplicant)"
    else
        log_warn "/dev/teepriv0 not found — tee-supplicant cannot serve OP-TEE"
    fi
    local rpmb; rpmb="$(find /dev -maxdepth 1 -name 'mmcblk*rpmb' 2>/dev/null | tr '\n' ' ')"
    if [ -n "${rpmb}" ]; then
        log_ok "RPMB partition: ${rpmb% }"
    else
        log_warn "No RPMB partition (/dev/mmcblk*rpmb)"
    fi
}

lib_fiovb_supplicant_service() {
    check_systemd_unit tee-supplicant.service || return 1
    fiocheck_static && return 0
    check_unit_active tee-supplicant.service "active|activating"
}

# Non-destructive read of a variable aktualizr-lite also reads
lib_fiovb_runtime_check() {
    dry_run "fiovb_printenv bootcount" && return 0
    require_runtime "fiovb_printenv" || return 0
    if ! command -v fiovb_printenv >/dev/null 2>&1; then
        log_skip "fiovb_printenv: not installed"
        return 0
    fi
    local out
    if out="$(fiovb_printenv bootcount 2>&1)"; then
        log_ok "fiovb_printenv bootcount: ${out:-empty}"
        return 0
    fi
    log_fail "fiovb_printenv bootcount failed: ${out} — TEE or RPMB issue"
    return 1
}

lib_fiovb_all() {
    lib_fiovb_kconfig
    lib_fiovb_lib_check
    lib_fiovb_cmd
    lib_fiovb_devices
    lib_fiovb_supplicant_service
    lib_fiovb_runtime_check
}
