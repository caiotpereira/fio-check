#!/usr/bin/env sh
# =============================================================================
# lib/foundries/lib_ostree.sh — OSTree integrity and sysroot checks
#
# OSTree is a content-addressable object store for OS deployments — often
# described as "git for operating systems".  It provides atomic, rollback-
# capable upgrades on a SINGLE partition: files are hardlinked from the
# shared object store into deployment directories, so no second partition or
# data copy is needed.  meta-lmp (kirkstone) pins ostree v2021.6 with five
# LmP-specific patches:
#   - Boot-directory support (U-Boot / systemd-boot)
#   - Atomic /boot/loader swap via renameat2
#   - ostree-prepare-root pivot into the deployed sysroot
#
# Architecture (deployed sysroot) — single-partition layout
#   /sysroot                       real root (bind-mounted at early boot)
#   /ostree → sysroot/ostree       top-level symlink
#   /sysroot/ostree/repo/          shared object store (hardlinked files)
#   /sysroot/ostree/deploy/lmp/    all deployments share objects via hardlinks
#   /boot/loader/                  EFI / U-Boot entries written by ostree
#   /boot/loader/entries/*.conf    per-deployment boot entries
#   /usr/lib/ostree/ostree-prepare-root  pivot-root binary (switchroot)
#
# Systemd services (from ostree and ostree-switchroot packages)
#   ostree-remount.service         makes / read-only after sysroot pivot
#   ostree-finalize-staged.path    watches /run/ostree for staged deployments
#   ostree-prepare-root.service    pivots initrd root into the deployed sysroot
#
# Kernel config requirements (from lmp-kernel-cache kirkstone)
#   CONFIG_OVERLAY_FS              ostree RRECOMMENDS kernel-module-overlay
#   CONFIG_MD                      device-mapper core (dm-verity stack)
#   CONFIG_BLK_DEV_DM              dm block device frontend
#   CONFIG_DM_VERITY               per-block hash verification for secure boot
#   CONFIG_TMPFS                   /var bind-mount and /run/ostree at early boot
#
# Build-time PACKAGECONFIG enabled in meta-lmp:
#   curl, libarchive, libmount, systemd, glib, soup
#   gpgme explicitly disabled (avoids GPLv3)
#
# OSTREE_OSNAME = "lmp"  (meta-lmp/conf/distro/lmp.conf)
#
# References
#   https://github.com/foundriesio/meta-lmp/tree/kirkstone
#   https://ostreedev.github.io/ostree/
#   https://docs.foundries.io/latest/reference-manual/linux/linux-lmp-fs.html
#
# Sourced by profiles; never executed directly.
# =============================================================================

[ -n "${_LIB_OSTREE_LOADED:-}" ] && return 0
_LIB_OSTREE_LOADED=1

# OSTREE_OSNAME as declared in meta-lmp/conf/distro/lmp.conf
_OSTREE_OSNAME="lmp"

# ---------------------------------------------------------------------------
# lib_ostree_kconfig — kernel requirements for OSTree deployments
#
# OverlayFS is needed for staged deployment snapshots.
# The device-mapper stack (MD + BLK_DEV_DM + DM_VERITY) is required for
# dm-verity verified-boot, which LmP enables for every rootfs deployment.
# TMPFS is needed for /var and /run/ostree at early boot.
# ---------------------------------------------------------------------------
lib_ostree_kconfig() {
    # ── OverlayFS — staged deployment snapshots ──────────────────────────────
    check_kconfig CONFIG_OVERLAY_FS

    # ── Device-mapper — dm-verity verified boot ──────────────────────────────
    check_kconfig CONFIG_MD              # device-mapper core
    check_kconfig CONFIG_BLK_DEV_DM     # dm block device frontend
    check_kconfig CONFIG_DM_VERITY       # per-block hash verification

    # ── tmpfs — /var bind-mount and ostree run directory ─────────────────────
    check_kconfig CONFIG_TMPFS
}

# ---------------------------------------------------------------------------
# lib_ostree_lib_check — shared library dependencies
#
# libostree-1 is consumed by aktualizr-lite and the ostree CLI itself.
# The meta-lmp PACKAGECONFIG enables: curl (HTTPS pulls), libarchive
# (archive unpacking), libmount (sysroot management), glib-2.0 (core dep).
# ---------------------------------------------------------------------------
lib_ostree_lib_check() {
    check_lib_dependency ostree-1     # libostree-1 — object store API
    check_lib_dependency glib-2.0    # GLib — required DEPENDS in base recipe
    check_lib_dependency curl         # HTTPS transport for ostree pulls
    check_lib_dependency archive      # libarchive — archive unpacking
    check_lib_dependency mount        # libmount — sysroot mount management
}

# ---------------------------------------------------------------------------
# lib_ostree_cmd — binary availability check
#
# /usr/bin/ostree is the main CLI used for admin, log, and diff operations.
# ---------------------------------------------------------------------------
lib_ostree_cmd() {
    check_cmd ostree
}

# ---------------------------------------------------------------------------
# lib_ostree_sysroot_check — deployed sysroot filesystem layout
#
# An ostree-deployed system has a fixed directory structure created during
# initial deployment.  All checks here are warn-only because some paths are
# only populated after the first successful OTA deployment.
# OSTREE_OSNAME="lmp" is set in meta-lmp/conf/distro/lmp.conf.
# ---------------------------------------------------------------------------
lib_ostree_sysroot_check() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        print_dryrun "lib_ostree_sysroot_check (dry-run: filesystem probes skipped)"
        return 0
    fi

    # ── /sysroot — real root bind-mounted from initrd ────────────────────────
    local sysroot="/sysroot"
    if [ -d "${sysroot}" ]; then
        log_ok "Sysroot: ${sysroot} present"
    else
        log_warn "Sysroot not found: ${sysroot} — not an ostree-deployed system"
        return 0
    fi

    # ── /ostree symlink or directory → sysroot/ostree ───────────────────────
    if [ -L "/ostree" ] || [ -d "/ostree" ]; then
        log_ok "OSTree root: /ostree present"
    else
        log_warn "OSTree root not found: /ostree — sysroot layout incomplete"
    fi

    # ── OSTree object store ──────────────────────────────────────────────────
    local repo="${sysroot}/ostree/repo"
    if [ -d "${repo}" ]; then
        log_ok "OSTree repo: ${repo}"
    else
        log_warn "OSTree repo not found: ${repo}"
    fi

    # ── LmP deployment directory (OSTREE_OSNAME=lmp) ────────────────────────
    local deploy_base="${sysroot}/ostree/deploy/${_OSTREE_OSNAME}"
    if [ -d "${deploy_base}" ]; then
        local deploy_count
        deploy_count="$(find "${deploy_base}/deploy" -maxdepth 1 -mindepth 1 \
            -type d 2>/dev/null | wc -l)"
        log_ok "OSTree deployment dir: ${deploy_base} (${deploy_count} deployment(s))"
    else
        log_warn "OSTree deploy dir not found: ${deploy_base} — OSTREE_OSNAME=${_OSTREE_OSNAME}"
    fi

    # ── /boot/loader — boot entries written by ostree ───────────────────────
    local boot_loader="/boot/loader"
    if [ -d "${boot_loader}" ] || [ -L "${boot_loader}" ]; then
        log_ok "Boot loader dir: ${boot_loader} present"
        local entry_count
        entry_count="$(find "${boot_loader}/entries" -name "*.conf" \
            2>/dev/null | wc -l)"
        [ "${entry_count}" -gt 0 ] \
            && log_ok "Boot entries: ${entry_count} entry/entries found in ${boot_loader}/entries"
    else
        log_warn "Boot loader dir not found: ${boot_loader} — ostree has not written boot entries"
    fi

    # ── ostree-prepare-root binary (ostree-switchroot package) ──────────────
    local prepare_root="/usr/lib/ostree/ostree-prepare-root"
    if [ -f "${prepare_root}" ]; then
        log_ok "Binary: ${prepare_root}"
    else
        log_warn "Binary not found: ${prepare_root} — ostree-switchroot package missing"
    fi
}

# ---------------------------------------------------------------------------
# lib_ostree_admin_status — live deployment status via ostree CLI
#
# `ostree admin status` lists current and pending deployments with their
# commit hashes.  Skipped when ostree is absent (non-LmP system).
# ---------------------------------------------------------------------------
lib_ostree_admin_status() {
    if [ "${FIOCHECK_DRY_RUN:-0}" -eq 1 ]; then
        print_dryrun "ostree admin status (dry-run: command not executed)"
        return 0
    fi

    if ! command -v ostree >/dev/null 2>&1; then
        log_skip "ostree admin status: ostree not on PATH"
        return 0
    fi

    local status_out
    if status_out="$(ostree admin status 2>&1)"; then
        log_ok "ostree admin status: succeeded"
        local active
        active="$(printf '%s\n' "${status_out}" | grep '^\*' | head -1 \
            | sed 's/^\* //' || true)"
        [ -n "${active}" ] && log_info "  Active deployment: ${active}"
    else
        log_warn "ostree admin status failed — not an ostree sysroot or sysroot not deployed"
    fi
}

# ---------------------------------------------------------------------------
# lib_ostree_service — systemd service state checks
#
# ostree-remount: makes / read-only after the sysroot pivot; must be enabled.
# ostree-prepare-root: static unit executed by the initrd — never "enabled"
#   but must be present on the deployed system.
# ---------------------------------------------------------------------------
lib_ostree_service() {
    check_systemd_service "ostree-remount" "enabled"
    check_systemd_service "ostree-prepare-root"
}

# ---------------------------------------------------------------------------
# lib_ostree_all — full ostree check suite
# ---------------------------------------------------------------------------
lib_ostree_all() {
    lib_ostree_kconfig
    lib_ostree_lib_check
    lib_ostree_cmd
    lib_ostree_sysroot_check
    lib_ostree_admin_status
    lib_ostree_service
}
