#!/usr/bin/env sh
# =============================================================================
# lib/foundries/lib_fiovb.sh
#     Foundries.io Verified Boot — fiovb host application (optee-fiovb)
#
# fiovb is the Foundries.io Verified Boot system for LmP.  It consists of
# two tightly coupled parts:
#
#   TA side  (secure world) — fiovb Pseudo Trusted Application (PTA) embedded
#            inside the OP-TEE firmware binary.  Runs in S-EL1 (OP-TEE core
#            context).  NOT a loadable *.ta file in /lib/optee_armtz — it is
#            baked into the OP-TEE image at build time.
#            Provides authenticated read/write access to RPMB via the eMMC
#            Replay Protected Memory Block partition.
#
#   CA side  (normal world) — the fiovb host application + libfiovb.
#            Uses libteec to call TEEC_OpenSession(TA_FIOVB_UUID) which
#            issues an ioctl to the Linux TEE driver (/dev/tee0), crosses
#            the TrustZone boundary, and invokes the PTA.
#
# What fiovb stores in RPMB (OTA / rollback variables)
#   upgrade_available          aktualizr-lite: update pending reboot
#   bootcount                  U-Boot: consecutive boot attempts
#   rollback_index             AVB rollback counter
#   bootupgrade_available      boot firmware upgrade pending
#   bootupgrade_primary_updated boot firmware write completed
#   is_secondary_boot          booted from secondary slot
#
# Communication path
#   userland (fiovb CA)
#     → libteec ioctl
#       → /dev/tee0 (Linux TEE driver, CONFIG_OPTEE)
#         → TrustZone (ARM secure world)
#           → OP-TEE (S-EL1)
#             → fiovb PTA
#               → RPMB (eMMC secure partition)
#
# Binary
#   /usr/bin/fiovb  (C, dynamically linked against libteec + libc)
#   Commands: fiovb_printenv <name>
#             fiovb_setenv   <name> <value>
#             fiovb_delenv   <name>
#
# Shared libraries
#   Required : libteec  (OP-TEE Client API — GlobalPlatform TEE Client API)
#   Optional : libfiovb (convenience wrapper, may be linked into aktualizr-lite)
#
# Device nodes
#   /dev/tee0      CA access to OP-TEE (world-readable with correct group)
#   /dev/teepriv0  tee-supplicant private access
#   /dev/mmcblkXrpmb  RPMB partition (accessed by OP-TEE, not directly by CA)
#
# Kernel config
#   Required: CONFIG_TEE, CONFIG_OPTEE, CONFIG_MMC, CONFIG_MMC_BLOCK
#   Required: CONFIG_MMC_BLOCK_MINORS (for /dev/mmcblkXrpmb)
#   Optional: CONFIG_OPTEE_INSECURE_LOAD_IMAGE (non-secure TA loading — not
#             needed since fiovb is a PTA embedded in OP-TEE firmware)
#
# References
#   https://github.com/foundriesio/optee-fiovb
#   https://docs.foundries.io/latest/reference-manual/security/secure-machines.html
#   https://docs.foundries.io/latest/reference-manual/security/secure-boot-imx-habv4.html
#
# Sourced by profiles; never executed directly.
# =============================================================================

[ -n "${_LIB_FIOVB_LOADED:-}" ] && return 0
_LIB_FIOVB_LOADED=1

# ---------------------------------------------------------------------------
# lib_fiovb_kconfig — kernel requirements
# ---------------------------------------------------------------------------
lib_fiovb_kconfig() {
    # ── TEE subsystem ────────────────────────────────────────────────────────
    check_kconfig CONFIG_TEE            # TEE subsystem core
    check_kconfig CONFIG_OPTEE          # OP-TEE driver (talks to secure world)

    # ── eMMC / RPMB ─────────────────────────────────────────────────────────
    # fiovb stores rollback counters in RPMB; the eMMC driver must be present.
    check_kconfig CONFIG_MMC
    check_kconfig CONFIG_MMC_BLOCK

    # ── ARM TrustZone ────────────────────────────────────────────────────────
    # fiovb is AArch64/AArch32 only — TrustZone is mandatory hardware.
    check_kconfig CONFIG_ARM64          # AArch64 (most LmP targets)
}

# ---------------------------------------------------------------------------
# lib_fiovb_lib_check — shared library dependencies
# ---------------------------------------------------------------------------
lib_fiovb_lib_check() {
    # libteec — OP-TEE Client API (GlobalPlatform TEE Client API spec).
    # The fiovb CA binary calls TEEC_InitializeContext / TEEC_OpenSession via
    # this library.  Hard required — fiovb will not run without it.
    check_lib_dependency teec "optee-client / libteec"
}

# ---------------------------------------------------------------------------
# lib_fiovb_cmd — binary and tooling checks
# ---------------------------------------------------------------------------
lib_fiovb_cmd() {
    # fiovb host CA binary
    check_cmd fiovb "optee-fiovb (meta-lmp / Foundries.io LmP image)"

    # tee-supplicant — the OP-TEE normal-world daemon.
    # Required for TA loading (even though fiovb is a PTA, tee-supplicant
    # manages the TEE session context and RPC operations from OP-TEE).
    check_cmd tee-supplicant "optee-client"
}

# ---------------------------------------------------------------------------
# lib_fiovb_devices — TEE and RPMB device node checks
# ---------------------------------------------------------------------------
lib_fiovb_devices() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_fiovb_devices (dry-run: device node probes skipped)"
        return 0
    fi

    # ── /dev/tee0 — CA access node ───────────────────────────────────────────
    log_info "Checking TEE CA device node: /dev/tee0"
    if [ -c /dev/tee0 ]; then
        log_ok "TEE device: /dev/tee0 present"
        # Check group permissions — CA must be in the 'tee' group or run as root
        local tee_group; tee_group="$(stat -c '%G' /dev/tee0 2>/dev/null || true)"
        local tee_perms; tee_perms="$(stat -c '%a' /dev/tee0 2>/dev/null || true)"
        log_info "  /dev/tee0: group=${tee_group} permissions=${tee_perms}"
        case "${tee_perms}" in
            660|666)
                log_ok "  /dev/tee0: accessible (permissions ${tee_perms})" ;;
            *)
                log_warn "  /dev/tee0: unexpected permissions ${tee_perms} — fiovb may need root" ;;
        esac
    else
        log_fail "/dev/tee0 not found — OP-TEE driver not loaded or device not present"
        return 1
    fi

    # ── /dev/teepriv0 — tee-supplicant private node ──────────────────────────
    log_info "Checking TEE supplicant device node: /dev/teepriv0"
    if [ -c /dev/teepriv0 ]; then
        log_ok "TEE device: /dev/teepriv0 present (tee-supplicant can connect)"
    else
        log_warn "/dev/teepriv0 not found — tee-supplicant may not function correctly"
    fi

    # ── RPMB partition ───────────────────────────────────────────────────────
    # fiovb accesses RPMB via OP-TEE (not directly from normal world).
    # We check for the RPMB block device as a sanity indicator.
    log_info "Checking RPMB partition"
    local rpmb_devs
    rpmb_devs="$(find /dev -maxdepth 1 -name 'mmcblk*rpmb' 2>/dev/null | sort | tr '\n' ' ')"
    rpmb_devs="${rpmb_devs% }"
    if [ -n "${rpmb_devs}" ]; then
        log_ok "RPMB partition(s) found: ${rpmb_devs}"
    else
        log_warn "No RPMB partition found (/dev/mmcblk*rpmb) — eMMC RPMB may not be available"
    fi
}

# ---------------------------------------------------------------------------
# lib_fiovb_supplicant_service — tee-supplicant systemd service check
# ---------------------------------------------------------------------------
lib_fiovb_supplicant_service() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_fiovb_supplicant_service (dry-run: systemctl probe skipped)"
        return 0
    fi

    log_info "Checking tee-supplicant service"

    if ! command -v systemctl >/dev/null 2>&1; then
        log_skip "tee-supplicant service check: systemctl not available"
        return 0
    fi

    local unit_line
    unit_line="$(systemctl list-unit-files "tee-supplicant.service" \
        --no-legend 2>/dev/null | head -1)"

    if [ -z "${unit_line}" ]; then
        log_warn "tee-supplicant.service: not found — tee-supplicant may be started by init script"
        # Fallback: check if the process is running
        if pgrep -x tee-supplicant >/dev/null 2>&1; then
            log_ok "tee-supplicant: process is running (no systemd unit)"
        else
            log_warn "tee-supplicant: not running — OP-TEE TA sessions will fail"
        fi
        return 0
    fi

    local enable_state; enable_state="$(printf '%s\n' "${unit_line}" | awk '{print $2}')"
    local active_state; active_state="$(systemctl is-active tee-supplicant 2>/dev/null || true)"

    local msg="tee-supplicant.service: enable=${enable_state} active=${active_state}"
    case "${active_state}" in
        active)     log_ok   "${msg}" ;;
        activating) log_ok   "${msg}" ;;
        failed)     log_fail "${msg} — check: journalctl -u tee-supplicant" ;;
        *)          log_warn "${msg} — tee-supplicant should be running for fiovb to work" ;;
    esac
}

# ---------------------------------------------------------------------------
# lib_fiovb_runtime_check — functional smoke test via fiovb_printenv
#
# Reads a well-known RPMB variable (upgrade_available) that aktualizr-lite
# also reads.  Non-destructive — printenv never modifies RPMB state.
# Only runs when fiovb binary and /dev/tee0 are both available.
# ---------------------------------------------------------------------------
lib_fiovb_runtime_check() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_fiovb_runtime_check (dry-run: fiovb_printenv skipped)"
        return 0
    fi

    log_info "fiovb runtime check: fiovb_printenv upgrade_available"

    if ! command -v fiovb >/dev/null 2>&1; then
        log_skip "fiovb runtime check: fiovb binary not available"
        return 0
    fi

    if [ ! -c /dev/tee0 ]; then
        log_skip "fiovb runtime check: /dev/tee0 not present"
        return 0
    fi

    local result rc=0
    result="$(fiovb fiovb_printenv upgrade_available 2>&1)" || rc=$?

    if [ "${rc}" -eq 0 ]; then
        log_ok "fiovb_printenv upgrade_available: succeeded (${result:-empty})"
    else
        # Distinguish between "variable not set" (expected on fresh device) and
        # a genuine TEE communication failure
        if echo "${result}" | grep -qi "not found\|no such\|TEEC_ERROR_ITEM_NOT_FOUND"; then
            log_ok "fiovb_printenv: TEE session OK (variable not yet set — expected on unregistered device)"
        else
            log_warn "fiovb_printenv upgrade_available: failed (${result}) — TEE or RPMB issue"
        fi
    fi
}

# ---------------------------------------------------------------------------
# lib_fiovb_all — full fiovb check suite
# ---------------------------------------------------------------------------
lib_fiovb_all() {
    lib_fiovb_kconfig
    lib_fiovb_lib_check
    lib_fiovb_cmd
    lib_fiovb_devices
    lib_fiovb_supplicant_service
    lib_fiovb_runtime_check
}
