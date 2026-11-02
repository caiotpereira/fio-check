#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_fio_diag.sh — on-device support bundle (fio-diag)
#
# Both layers install /usr/sbin/fio-diag.sh from foundriesio/lmp-tools
# (FR-17, MAY). fioconfig's diag action calls it.
#
# Expectations
#   FIOCHECK_FIO_DIAG_RUN   1: run fio-diag.sh and require output (default 0)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_FIO_DIAG_LOADED:-}" ] && return 0
_LIB_FIO_DIAG_LOADED=1

lib_fio_diag_cmd() {
    check_file /usr/sbin/fio-diag.sh x
}

lib_fio_diag_run() {
    dry_run "fio-diag.sh" && return 0
    if [ "${FIOCHECK_FIO_DIAG_RUN:-0}" != "1" ]; then
        log_skip "fio-diag.sh run (set FIOCHECK_FIO_DIAG_RUN=1 to enable)"
        return 0
    fi
    require_runtime "fio-diag.sh" || return 0
    local out; out="$(/usr/sbin/fio-diag.sh 2>&1)"
    if [ -n "${out}" ]; then
        log_ok "fio-diag.sh: produced $(printf '%s\n' "${out}" | wc -l | tr -d ' ') lines"
        return 0
    fi
    log_fail "fio-diag.sh: no output"
    return 1
}

lib_fio_diag_all() {
    lib_fio_diag_cmd
    lib_fio_diag_run
}
