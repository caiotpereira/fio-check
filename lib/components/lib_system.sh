#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_system.sh — image-wide checks
#
#   os-release fields          LMP_FACTORY_TAG and friends
#   development credentials    SR-13: none in production images
#   storage                    TR-10: free space for updates on /var
#   clock                      TR-09: TUF expiry needs a synced clock
#   watchdog                   FR-25: hardware watchdog wired to systemd
#
# Expectations
#   FIOCHECK_OS_RELEASE        "KEY=value" (exact) or "KEY" (present) entries
#                              for /etc/os-release (empty: report only)
#   FIOCHECK_DEV_USERS         development users (default "fio")
#   FIOCHECK_MIN_FREE_MB       minimum free MB on /var (empty: report only)
#   FIOCHECK_WATCHDOG          yes: /dev/watchdog and RuntimeWatchdogSec required
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_SYSTEM_LOADED:-}" ] && return 0
_LIB_SYSTEM_LOADED=1

: "${FIOCHECK_DEV_USERS:=fio}"

# _os_release_file — /etc/os-release or its /usr/lib target
_os_release_file() {
    local f
    for f in /etc/os-release /usr/lib/os-release; do
        [ -f "$(fiocheck_path "${f}")" ] && { printf '%s' "${f}"; return; }
    done
}

lib_system_os_release() {
    dry_run "lib_system_os_release" && return 0
    local f; f="$(_os_release_file)"
    if [ -z "${f}" ]; then
        log_fail "os-release: /etc/os-release not found"
        return 1
    fi
    local p; p="$(fiocheck_path "${f}")"
    log_info "os-release: $(grep -E '^PRETTY_NAME=' "${p}" | cut -d= -f2- | tr -d '"')"
    local rc=0 e key val actual
    for e in ${FIOCHECK_OS_RELEASE:-}; do
        key="${e%%=*}"
        actual="$(grep -E "^${key}=" "${p}" | head -n 1 | cut -d= -f2- | tr -d '"')"
        if [ "${e}" = "${key}" ]; then
            if grep -qE "^${key}=" "${p}"; then
                log_ok "os-release: ${key}=${actual}"
            else
                log_fail "os-release: ${key} missing"
                rc=1
            fi
            continue
        fi
        val="${e#*=}"
        if [ "${actual}" = "${val}" ]; then
            log_ok "os-release: ${key}=${actual}"
        else
            log_fail "os-release: ${key}=${actual:-unset} — expected ${val}"
            rc=1
        fi
    done
    return "${rc}"
}

# ---------------------------------------------------------------------------
# SR-13: production images carry no development user, no password sudo rule,
# and a locked root. Development images only report.
# ---------------------------------------------------------------------------
lib_system_dev_credentials() {
    dry_run "lib_system_dev_credentials (passwd, shadow, sudoers)" && return 0
    local rc=0 u passwd shadow sudoers
    passwd="$(fiocheck_path /etc/passwd)"
    shadow="$(fiocheck_path /etc/shadow)"
    sudoers="$(fiocheck_path /etc/sudoers.d)"

    local found=""
    for u in ${FIOCHECK_DEV_USERS}; do
        grep -q "^${u}:" "${passwd}" 2>/dev/null && found="${found} ${u}"
    done
    local sudo_frag=""
    [ -d "${sudoers}" ] && sudo_frag="$(grep -lE '^[^#].*ALL' "${sudoers}"/* 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')"
    local root_pw=""
    if [ -r "${shadow}" ]; then
        root_pw="$(grep '^root:' "${shadow}" | cut -d: -f2)"
    elif ! fiocheck_static; then
        log_skip "Credentials: /etc/shadow not readable (run as root)"
    fi

    if ! fiocheck_production; then
        [ -n "${found}" ] && log_info "Credentials: development user(s):${found} (dev mode)"
        [ -n "${sudo_frag}" ] && log_info "Credentials: sudoers fragments: ${sudo_frag}(dev mode)"
        [ -r "${shadow}" ] && [ -z "${root_pw}" ] && log_info "Credentials: root has an empty password (dev mode)"
        return 0
    fi

    if [ -n "${found}" ]; then
        log_fail "Credentials: development user(s) in a production image:${found}"
        rc=1
    else
        log_ok "Credentials: no development user (${FIOCHECK_DEV_USERS})"
    fi
    if [ -n "${sudo_frag}" ]; then
        log_fail "Credentials: sudoers fragments in a production image: ${sudo_frag}"
        rc=1
    else
        log_ok "Credentials: no sudoers fragment"
    fi
    if [ -r "${shadow}" ]; then
        case "${root_pw}" in
            '!'*|'*'*) log_ok "Credentials: root is locked" ;;
            *)         log_fail "Credentials: root is not locked"; rc=1 ;;
        esac
    fi
    return "${rc}"
}

# TR-10: room for an update on /var
lib_system_storage() {
    dry_run "df /var" && return 0
    require_runtime "free space on /var" || return 0
    local free; free="$(df -Pk /var 2>/dev/null | awk 'NR==2 { print int($4/1024) }')"
    if [ -z "${free}" ]; then
        log_fail "Storage: cannot read free space on /var"
        return 1
    fi
    local min="${FIOCHECK_MIN_FREE_MB:-}"
    if [ -z "${min}" ]; then
        log_info "Storage: ${free} MB free on /var"
        return 0
    fi
    if [ "${free}" -ge "${min}" ]; then
        log_ok "Storage: ${free} MB free on /var (>= ${min} MB)"
        return 0
    fi
    log_fail "Storage: ${free} MB free on /var — required >= ${min} MB"
    return 1
}

# TR-09: TUF metadata expiry is judged against the system clock
lib_system_clock() {
    dry_run "timedatectl NTPSynchronized" && return 0
    require_runtime "clock synchronization" || return 0
    if ! command -v timedatectl >/dev/null 2>&1; then
        log_skip "Clock: timedatectl not available"
        return 0
    fi
    local sync; sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null)"
    case "${sync}" in
        yes) log_ok "Clock: NTP synchronized ($(date -u '+%Y-%m-%dT%H:%M:%SZ'))" ;;
        no)  log_warn "Clock: not synchronized — TUF metadata expiry checks may fail" ;;
        *)   log_skip "Clock: synchronization state unknown" ;;
    esac
}

# FR-25: hardware watchdog and the systemd runtime watchdog
lib_system_watchdog() {
    dry_run "watchdog configuration" && return 0
    local cfg; cfg="$(cat "$(fiocheck_path /etc/systemd/system.conf)" \
        "$(fiocheck_path /etc/systemd/system.conf.d)"/*.conf \
        "$(fiocheck_path /usr/lib/systemd/system.conf.d)"/*.conf 2>/dev/null \
        | grep -E '^RuntimeWatchdogSec=' | tail -n 1 | cut -d= -f2)"
    local rc=0
    if [ "${FIOCHECK_WATCHDOG:-}" = "yes" ]; then
        case "${cfg}" in
            ""|0|off) log_fail "Watchdog: RuntimeWatchdogSec not set in systemd configuration"; rc=1 ;;
            *)        log_ok "Watchdog: RuntimeWatchdogSec=${cfg}" ;;
        esac
    else
        log_info "Watchdog: RuntimeWatchdogSec=${cfg:-unset}"
    fi
    fiocheck_static && return "${rc}"
    if [ -c /dev/watchdog ] || [ -c /dev/watchdog0 ]; then
        log_ok "Watchdog: device present"
    elif [ "${FIOCHECK_WATCHDOG:-}" = "yes" ]; then
        log_fail "Watchdog: no /dev/watchdog device"
        rc=1
    else
        log_info "Watchdog: no /dev/watchdog device"
    fi
    return "${rc}"
}

lib_system_all() {
    lib_system_os_release
    lib_system_dev_credentials
    lib_system_storage
    lib_system_clock
    lib_system_watchdog
}
