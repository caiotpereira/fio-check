#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_ostree.sh — OSTree deployment
#
# OSTree keeps OS deployments in a content-addressed object store and switches
# between them atomically; the stateroot ("osname") names the deployment tree:
#   /sysroot/ostree/repo                     object store
#   /sysroot/ostree/deploy/<osname>/deploy/  deployments
#   /sysroot/ostree/deploy/<osname>/var      persistent /var
#   /boot/loader/entries/*.conf              boot entries
# meta-lmp sets OSTREE_OSNAME = "lmp"; meta-updater (meta-foundries nodistro)
# defaults to the distro name. TR-07 makes an osname mismatch a regression.
#
# Expectations
#   FIOCHECK_OSTREE_OSNAME    expected stateroot (empty: report only)
#   FIOCHECK_OSTREE_UNITS     units that must be present (default ostree-remount.service)
#   FIOCHECK_OSTREE_KCONFIG   CONFIG_ symbols the kernel needs (empty: skip)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_OSTREE_LOADED:-}" ] && return 0
_LIB_OSTREE_LOADED=1

: "${FIOCHECK_OSTREE_UNITS:=ostree-remount.service}"

lib_ostree_kconfig() {
    local rc=0 sym
    if [ -z "${FIOCHECK_OSTREE_KCONFIG:-}" ]; then
        log_skip "ostree kconfig: no FIOCHECK_OSTREE_KCONFIG expectation"
        return 0
    fi
    for sym in ${FIOCHECK_OSTREE_KCONFIG}; do
        check_kconfig "${sym}" || rc=1
    done
    return "${rc}"
}

lib_ostree_lib_check() {
    check_lib_dependency ostree-1
}

lib_ostree_cmd() {
    check_cmd ostree "ostree"
}

# ---------------------------------------------------------------------------
# Sysroot layout and stateroot (live: the booted sysroot)
# ---------------------------------------------------------------------------
lib_ostree_sysroot_check() {
    dry_run "lib_ostree_sysroot_check (sysroot layout)" && return 0
    require_runtime "ostree sysroot" || return 0
    if [ ! -d /sysroot/ostree ]; then
        log_fail "OSTree sysroot: /sysroot/ostree not found — not an ostree-deployed system"
        return 1
    fi
    log_ok "OSTree sysroot: /sysroot/ostree"
    check_file /sysroot/ostree/repo d "OSTree repo: /sysroot/ostree/repo"

    local osnames
    osnames="$(find /sysroot/ostree/deploy -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | sed 's|.*/||' | tr '\n' ' ')"
    osnames="${osnames% }"
    local expected="${FIOCHECK_OSTREE_OSNAME:-}"
    if [ -z "${expected}" ]; then
        log_info "OSTree stateroot(s): ${osnames:-none}"
    elif [ -d "/sysroot/ostree/deploy/${expected}" ]; then
        log_ok "OSTree stateroot: ${expected}"
    else
        log_fail "OSTree stateroot: '${expected}' not found (found: ${osnames:-none})"
        return 1
    fi

    local entries
    entries="$(find /boot/loader/entries -name '*.conf' 2>/dev/null | wc -l | tr -d ' ')"
    if [ "${entries}" -gt 0 ]; then
        log_ok "Boot entries: ${entries} in /boot/loader/entries"
    else
        log_warn "Boot entries: none in /boot/loader/entries"
    fi
}

# ---------------------------------------------------------------------------
# ostree admin status — booted deployment belongs to the expected stateroot
# ---------------------------------------------------------------------------
lib_ostree_admin_status() {
    dry_run "ostree admin status" && return 0
    require_runtime "ostree admin status" || return 0
    if ! command -v ostree >/dev/null 2>&1; then
        log_skip "ostree admin status: ostree not installed"
        return 0
    fi
    local out
    if ! out="$(ostree admin status 2>&1)"; then
        log_fail "ostree admin status failed — not an ostree sysroot"
        return 1
    fi
    local booted; booted="$(printf '%s\n' "${out}" | grep '^\*' | head -n 1 | sed 's/^\* //')"
    log_ok "ostree admin status: booted ${booted:-unknown}"
    local expected="${FIOCHECK_OSTREE_OSNAME:-}"
    if [ -n "${expected}" ] && [ -n "${booted}" ]; then
        case "${booted}" in
            "${expected} "*) log_ok "Booted deployment stateroot: ${expected}" ;;
            *) log_fail "Booted deployment stateroot: '${booted%% *}' — expected ${expected}"; return 1 ;;
        esac
    fi
}

lib_ostree_service() {
    local rc=0 u
    for u in ${FIOCHECK_OSTREE_UNITS}; do
        check_systemd_unit "${u}" || rc=1
    done
    return "${rc}"
}

lib_ostree_all() {
    lib_ostree_kconfig
    lib_ostree_lib_check
    lib_ostree_cmd
    lib_ostree_service
    lib_ostree_sysroot_check
    lib_ostree_admin_status
}
