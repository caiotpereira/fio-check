#!/usr/bin/env sh
# =============================================================================
# fio-check.sh — Foundries.io device image checker
#
# Validates that a device image built with meta-lmp or meta-foundries carries
# the expected components. Runs on the device (live checks) or against an
# unbooted rootfs (--root, static checks only).
#
# Portability: POSIX sh plus `local`. Runs under bash, dash and busybox ash
# with only busybox applets (GPLv3-free images): no GNU-only options, no
# legacy `head -N`, no `cat -v`.
#
# Usage:   ./fio-check.sh list | run <target> | check <kind> <args> [OPTIONS]
#          (see: ./fio-check.sh help)
#
# Exit codes:
#   0  no check failed
#   1  one or more checks failed
#   2  usage error
# =============================================================================

# =============================================================================
#  Global Variables
# =============================================================================
SCRIPT_VERSION="0.2.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NO_COLOR=0          # disable colored output
NO_WARNING=0        # --warn-as-fail: a warning counts as a failure
VERBOSE=0           # print the probe behind each check
QUIET=0             # print failures and the summary only
DRY_RUN=0           # list the checks without executing them
FILTER=""           # --filter: ok,fail,warn,skip,info
DETAILED=0          # list -v: also list lib functions
REPORT_FILE=""      # -r: plain-text report
EXPECT=""           # --expect: expectation set (profiles/<layer>/expect/<name>.sh)
MACHINE=""          # --machine: machine file (profiles/<layer>/machine/<name>.sh)

export FIO_TEST_LIB="${SCRIPT_DIR}/lib"
export FIO_TEST_PROFILES="${SCRIPT_DIR}/profiles"
export FIO_TEST_FILTER=""
export FIOCHECK_DRY_RUN=0
export FIOCHECK_ROOT=""          # --root: check an unbooted rootfs (static checks only)
export FIOCHECK_KCONFIG=""       # --kconfig: kernel .config (plain or .gz)
export FIOCHECK_MODE="dev"       # --mode: dev | production
export FIOCHECK_PROFILE_DIR=""   # directory of the profile being run

# =============================================================================
#  Internal Variables
# =============================================================================
_REPORT_LINES=""
_PROFILE_LOADED=""
_TEST_PASS=0
_TEST_FAIL=0
_TEST_WARN=0
_TEST_SKIP=0
_FIOCHECK_REQ=""     # requirement tag prefixed to every result (fiocheck_req)
_KCONFIG_STATE=""    # "" = not resolved, "none" = unavailable, else a file path
_KCONFIG_TMP=""      # decompressed copy of a .gz kernel config
_KCONFIG_WARNED=0

# =============================================================================
#  Terminal output
# =============================================================================
_color() {
    [ 1 -eq "${NO_COLOR}" ] && printf '%s' "$2" && return
    printf '\033[%sm%s\033[0m' "$1" "$2"
}
_color_red()    { _color "0;31" "$*"; }
_color_green()  { _color "0;32" "$*"; }
_color_yellow() { _color "0;33" "$*"; }
_color_blue()   { _color "0;34" "$*"; }
_color_cyan()   { _color "0;36" "$*"; }
_color_bold()   { _color "1" "$*"; }
_color_dim()    { _color "2" "$*"; }

print_skip()     { [ "${QUIET}" -eq 1   ] && return; printf ' %s %s\n' "$(_color_dim    '[SKIP]')" "$*";}
print_info()     { [ "${QUIET}" -eq 1   ] && return; printf ' %s %s\n' "$(_color_blue   '[INFO]')" "$*";}
print_ok()       { [ "${QUIET}" -eq 1   ] && return; printf ' %s %s\n' "$(_color_green  '[ OK ]')" "$*";}
print_fail()     {                                   printf ' %s %s\n' "$(_color_red    '[FAIL]')" "$*" >&2;}
print_warn()     { [ "${QUIET}" -eq 1   ] && return; printf ' %s %s\n' "$(_color_yellow '[WARN]')" "$*";}
print_section()  { [ "${QUIET}" -eq 1   ] && return; printf '\n%s\n'   "$(_color_bold "== $*  ")"; }
print_verbose()  { [ "${VERBOSE}" -eq 1 ] && printf '  %s %s\n' "$(_color_dim '[VERB]')" "$*" || true; }
print_dryrun()   { printf ' %s %s\n' "$(_color_dim '[DRY ]')" "$(_color_yellow "$*")"; }

# _rule <width> — a horizontal rule (multibyte-safe, no seq)
_rule() {
    local n="$1" s=""
    while [ "${n}" -gt 0 ]; do s="${s}─"; n=$(( n - 1 )); done
    printf '%s' "${s}"
}

# =============================================================================
#  Result logging — every check reports through these
# =============================================================================
_log_report() {
    if [ -z "${_REPORT_LINES}" ]; then
        _REPORT_LINES="$*"
    else
        _REPORT_LINES="${_REPORT_LINES}
$*"
    fi
}

# _filter <type> — 0 when results of <type> are shown
_filter() {
    [ -z "${FILTER}" ] && return 0
    case ",${FILTER}," in *",$1,"*) return 0 ;; esac
    return 1
}

# _tag <text> — prefix the active requirement tag
_tag() {
    if [ -n "${_FIOCHECK_REQ}" ]; then printf '[%s] %s' "${_FIOCHECK_REQ}" "$*"; else printf '%s' "$*"; fi
}

log_ok() {
    local m; m="$(_tag "$*")"
    _log_report "[ OK ] ${m}"
    _TEST_PASS=$(( _TEST_PASS + 1 ))
    _filter ok && print_ok "${m}" || true
}

log_skip() {
    local m; m="$(_tag "$*")"
    _log_report "[SKIP] ${m}"
    _TEST_SKIP=$(( _TEST_SKIP + 1 ))
    _filter skip && print_skip "${m}" || true
}

log_fail() {
    local m; m="$(_tag "$*")"
    _log_report "[FAIL] ${m}"
    _TEST_FAIL=$(( _TEST_FAIL + 1 ))
    _filter fail && print_fail "${m}" || true
}

log_warn() {
    if [ "${NO_WARNING}" -eq 1 ]; then
        log_fail "$*"
        return
    fi
    local m; m="$(_tag "$*")"
    _log_report "[WARN] ${m}"
    _TEST_WARN=$(( _TEST_WARN + 1 ))
    _filter warn && print_warn "${m}" || true
}

log_info() {
    local m; m="$(_tag "$*")"
    _log_report "[INFO] ${m}"
    _filter info && print_info "${m}" || true
}

# =============================================================================
#  Context helpers — used by libs and profiles
# =============================================================================

# fiocheck_req <ID> [title] — tag the following results with requirement ID
# (e.g. FR-10). With a title, also prints a section header. No args: clear.
fiocheck_req() {
    _FIOCHECK_REQ="${1:-}"
    [ -n "${2:-}" ] && print_section "${1} — ${2}"
    return 0
}

# dry_run <description> — in --dry-run print the description and return 0,
# otherwise return 1. Usage: dry_run "probe something" && return 0
dry_run() {
    [ "${DRY_RUN}" -eq 1 ] || return 1
    print_dryrun "$*"
    return 0
}

# fiocheck_static — 0 when checking an unbooted rootfs (--root)
fiocheck_static() { [ -n "${FIOCHECK_ROOT}" ]; }

# require_runtime <description> — return 1 (and log SKIP) in --root mode.
# Usage: require_runtime "docker daemon" || return 0
require_runtime() {
    fiocheck_static || return 0
    log_skip "$* — needs a running system (--root mode)"
    return 1
}

# fiocheck_path <absolute path> — the path inside the checked root
fiocheck_path() { printf '%s%s' "${FIOCHECK_ROOT}" "$1"; }

# fiocheck_production — 0 when --mode production
fiocheck_production() { [ "${FIOCHECK_MODE}" = "production" ]; }

# fiocheck_registered — 0 when the device has completed registration
fiocheck_registered() { [ -f "$(fiocheck_path /var/sota/sota.toml)" ]; }

# _systemd_running — 0 when a live systemd instance manages this system
_systemd_running() {
    ! fiocheck_static && [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1
}

# _ere_escape <text> — escape ERE metacharacters
_ere_escape() { printf '%s' "$1" | sed 's/[].[^$*+?(){}|\\]/\\&/g'; }

# =============================================================================
#  Library checks
# =============================================================================

# check_lib_dependency <library> [min_version]
# <library> with or without the "lib" prefix: "ssl", "libssl", "ostree-1".
# Lookup order, first hit wins:
#   1. pkg-config (live only; the only tier that can verify min_version)
#   2. ldconfig -p cache (live only; exact soname match)
#   3. find under the library directories (also used with --root)
check_lib_dependency() {
    local lib="${1:?check_lib_dependency: library name required}"
    local min_ver="${2:-}"
    local base="${lib#lib}"

    dry_run "check_lib_dependency lib${base}${min_ver:+ min_ver=${min_ver}}" && return 0

    local found=0 ver="" name
    if ! fiocheck_static && command -v pkg-config >/dev/null 2>&1; then
        for name in "${lib}" "lib${base}" "${base}"; do
            print_verbose "pkg-config --exists ${name}"
            pkg-config --exists "${name}" 2>/dev/null || continue
            ver="$(pkg-config --modversion "${name}" 2>/dev/null || true)"
            if [ -n "${min_ver}" ]; then
                if pkg-config --atleast-version="${min_ver}" "${name}" 2>/dev/null; then
                    log_ok "Library: lib${base} ${ver} (>= ${min_ver})"
                    return 0
                fi
                log_fail "Library: lib${base} ${ver} — required >= ${min_ver}"
                return 1
            fi
            log_ok "Library: lib${base} ${ver}"
            return 0
        done
    fi

    if ! fiocheck_static && command -v ldconfig >/dev/null 2>&1; then
        local pat; pat="$(_ere_escape "lib${base}")"
        print_verbose "ldconfig -p | grep -E '[[:space:]]${pat}\\.so'"
        if ldconfig -p 2>/dev/null | grep -qE "^[[:space:]]*${pat}\.so([. ]|$)"; then
            found=1
        fi
    fi

    if [ "${found}" -eq 0 ]; then
        local d dirs=""
        for d in /lib /usr/lib /usr/local/lib /lib64 /usr/lib64 /lib32 /usr/lib32; do
            [ -d "$(fiocheck_path "${d}")" ] && dirs="${dirs} $(fiocheck_path "${d}")"
        done
        print_verbose "find${dirs} -name lib${base}.so*"
        # shellcheck disable=SC2086
        if [ -n "${dirs}" ] && [ -n "$(find ${dirs} -maxdepth 3 -name "lib${base}.so*" 2>/dev/null | head -n 1)" ]; then
            found=1
        fi
    fi

    if [ "${found}" -eq 1 ]; then
        log_ok "Library: lib${base}"
        [ -n "${min_ver}" ] && log_skip "Library: lib${base} — version >= ${min_ver} not verifiable (no pkg-config)"
        return 0
    fi
    log_fail "Library: lib${base} — NOT FOUND"
    return 1
}

# check_lib_dependencies <lib1> [lib2 ...]
check_lib_dependencies() {
    print_section "Library Dependencies"
    local rc=0 lib
    for lib in "$@"; do
        check_lib_dependency "${lib}" || rc=1
    done
    return "${rc}"
}

# =============================================================================
#  Kernel checks
# =============================================================================

# check_sysctl <parameter> <expected_value>
check_sysctl() {
    local param="${1:?check_sysctl: parameter required}"
    local expected="${2:-}"

    dry_run "sysctl -n ${param}" && return 0
    require_runtime "sysctl ${param}" || return 0
    if ! command -v sysctl >/dev/null 2>&1; then
        log_fail "sysctl: command not available"
        return 1
    fi
    local val; val="$(sysctl -n "${param}" 2>/dev/null)"
    print_verbose "sysctl -n ${param} -> ${val}"
    if [ "${val}" = "${expected}" ]; then
        log_ok "Kernel parameter: ${param} = ${val}"
        return 0
    fi
    log_fail "Kernel parameter: ${param} expected ${expected}, configured ${val:-unset}"
    return 1
}

# _kconfig_resolve — set _KCONFIG_STATE to a readable plain-text config or "none"
# Order: --kconfig FILE, then (--root) <root>/boot/config-*, then (live)
# /proc/config.gz, /boot/config-$(uname -r), /boot/config.
_kconfig_resolve() {
    [ -n "${_KCONFIG_STATE}" ] && return 0
    local src="" f
    if [ -n "${FIOCHECK_KCONFIG}" ]; then
        src="${FIOCHECK_KCONFIG}"
    elif fiocheck_static; then
        for f in "${FIOCHECK_ROOT}"/boot/config-* "${FIOCHECK_ROOT}/boot/config"; do
            [ -r "${f}" ] && { src="${f}"; break; }
        done
    else
        for f in /proc/config.gz "/boot/config-$(uname -r)" /boot/config; do
            [ -r "${f}" ] && { src="${f}"; break; }
        done
    fi
    if [ -z "${src}" ] || [ ! -r "${src}" ]; then
        _KCONFIG_STATE="none"
        return 0
    fi
    case "${src}" in
        *.gz)
            _KCONFIG_TMP="$(mktemp)"
            zcat "${src}" > "${_KCONFIG_TMP}" 2>/dev/null
            _KCONFIG_STATE="${_KCONFIG_TMP}" ;;
        *)  _KCONFIG_STATE="${src}" ;;
    esac
    print_verbose "kernel config: ${src}"
}

# check_kconfig <CONFIG_SYMBOL> [expected_value]
# expected_value: y, m, n or a literal value. Default: y or m.
# A missing kernel config is a WARN (once), never a pass.
check_kconfig() {
    local symbol="${1:?check_kconfig: CONFIG symbol required}"
    local expected="${2:-}"
    symbol="${symbol#CONFIG_}"

    dry_run "check_kconfig CONFIG_${symbol}${expected:+ expected=${expected}}" && return 0

    _kconfig_resolve
    if [ "${_KCONFIG_STATE}" = "none" ]; then
        if [ "${_KCONFIG_WARNED}" -eq 0 ]; then
            _KCONFIG_WARNED=1
            log_warn "kconfig: no kernel config found — kernel checks not verified (provide one with --kconfig FILE)"
        fi
        log_skip "kconfig: CONFIG_${symbol} — no kernel config"
        return 0
    fi

    local value
    value="$(grep -E "^CONFIG_${symbol}=" "${_KCONFIG_STATE}" 2>/dev/null | cut -d= -f2-)"
    print_verbose "grep ^CONFIG_${symbol}= -> ${value:-<unset>}"

    if [ -n "${expected}" ]; then
        if [ "${expected}" = "n" ] && [ -z "${value}" ]; then
            log_ok "kconfig: CONFIG_${symbol} is not set"
            return 0
        fi
        if [ "${value}" = "${expected}" ]; then
            log_ok "kconfig: CONFIG_${symbol}=${value}"
            return 0
        fi
        log_fail "kconfig: CONFIG_${symbol} expected=${expected}, got=${value:-not set}"
        return 1
    fi
    case "${value}" in
        y|m) log_ok "kconfig: CONFIG_${symbol}=${value}"; return 0 ;;
    esac
    log_fail "kconfig: CONFIG_${symbol} is not enabled"
    return 1
}

# =============================================================================
#  Command checks
# =============================================================================

# _find_cmd <command> — print the path of <command>, or nothing
# Live: command -v. --root: searches the root's bin directories.
_find_cmd() {
    if ! fiocheck_static; then
        command -v "$1" 2>/dev/null
        return
    fi
    local d p
    for d in /usr/bin /bin /usr/sbin /sbin /usr/libexec /usr/local/bin; do
        p="${FIOCHECK_ROOT}${d}/$1"
        if [ -e "${p}" ] || [ -L "${p}" ]; then
            printf '%s\n' "${d}/$1"
            return
        fi
    done
}

# check_cmd <command> [install_hint]
check_cmd() {
    local cmd="${1:?check_cmd: command name required}"
    local hint="${2:-}"

    dry_run "check_cmd ${cmd}" && return 0
    local path; path="$(_find_cmd "${cmd}")"
    print_verbose "which ${cmd} -> ${path:-<none>}"
    if [ -z "${path}" ]; then
        log_fail "Command missing: ${cmd}${hint:+ (provided by: ${hint})}"
        return 1
    fi
    log_ok "Command exists: ${cmd}"
    return 0
}

# check_cmds <cmd1> [cmd2 ...]
check_cmds() {
    print_section "Command Checks"
    local rc=0 cmd
    for cmd in "$@"; do
        check_cmd "${cmd}" || rc=1
    done
    return "${rc}"
}

# check_absent_cmd <cmd1> [cmd2 ...] — each command must NOT be installed
check_absent_cmd() {
    local rc=0 cmd path
    for cmd in "$@"; do
        dry_run "check_absent_cmd ${cmd}" && continue
        path="$(_find_cmd "${cmd}")"
        if [ -n "${path}" ]; then
            log_fail "Command must be absent: ${cmd} (found ${path})"
            rc=1
        else
            log_ok "Command absent: ${cmd}"
        fi
    done
    return "${rc}"
}

# _compare_versions <a> <b> — 0: a == b, 1: a > b, 2: a < b
# Segments are compared numerically; a non-numeric suffix ("2-rc1") is ignored.
_compare_versions() {
    local a="$1" b="$2" sa sb
    while [ -n "${a}" ] || [ -n "${b}" ]; do
        sa="${a%%.*}"; sb="${b%%.*}"
        if [ "${a}" = "${sa}" ]; then a=""; else a="${a#*.}"; fi
        if [ "${b}" = "${sb}" ]; then b=""; else b="${b#*.}"; fi
        sa="${sa%%[!0-9]*}"; sb="${sb%%[!0-9]*}"
        sa="${sa:-0}"; sb="${sb:-0}"
        [ "${sa}" -gt "${sb}" ] && return 1
        [ "${sa}" -lt "${sb}" ] && return 2
    done
    return 0
}

# check_cmd_version <command> <expected> [version_args] [version_regex] [exact]
#
#   expected      minimum version (or the exact string when exact=true).
#                 Empty: report the version without enforcing it.
#   version_args  arguments printing the version (default: --version);
#                 word-split, so "compose version" works
#   version_regex ERE matching the version string itself
#                 (default: [0-9]+(\.[0-9]+)+)
#   exact         true: string comparison instead of minimum version
#
# Returns 0 ok, 1 missing / unparsable / too old / mismatch.
check_cmd_version() {
    local cmd="${1:?check_cmd_version: command name required}"
    local expected="${2:-}"
    local vargs="${3:---version}"
    local regex="${4:-[0-9]+(\.[0-9]+)+}"
    local exact="${5:-false}"

    dry_run "check_cmd_version ${cmd}${expected:+ ${expected}}" && return 0
    if fiocheck_static; then
        log_skip "Version: ${cmd} — not executed in --root mode"
        return 0
    fi
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        log_fail "Version: ${cmd} — command missing"
        return 1
    fi

    local raw version
    # shellcheck disable=SC2086
    raw="$("${cmd}" ${vargs} 2>&1)"
    version="$(printf '%s\n' "${raw}" | grep -oE "${regex}" | head -n 1)"
    print_verbose "${cmd} ${vargs} | grep -oE '${regex}' -> ${version:-<none>}"

    if [ -z "${version}" ]; then
        log_fail "Version: could not parse the version of ${cmd} (${cmd} ${vargs})"
        log_info "      Raw output: $(printf '%s' "${raw}" | head -n 1)"
        return 1
    fi
    if [ -z "${expected}" ]; then
        log_info "Version: ${cmd} ${version} (not enforced)"
        return 0
    fi
    if [ "${exact}" = "true" ]; then
        if [ "${version}" = "${expected}" ]; then
            log_ok "Version: ${cmd} ${version} = ${expected}"
            return 0
        fi
        log_fail "Version: ${cmd} ${version} — expected ${expected}"
        return 1
    fi
    _compare_versions "${version}" "${expected}"
    if [ $? -eq 2 ]; then
        log_fail "Version: ${cmd} ${version} — required >= ${expected}"
        return 1
    fi
    log_ok "Version: ${cmd} ${version} (>= ${expected})"
    return 0
}

# =============================================================================
#  File checks — all paths are absolute inside the checked root
# =============================================================================

# check_file <path> [type] [description]
# type: f file (default), d directory, x executable, l symlink, e any, S socket
check_file() {
    local path="${1:?check_file: path required}"
    local type="${2:-f}"
    local desc="${3:-${path}}"

    dry_run "check_file ${path} (${type})" && return 0
    local p; p="$(fiocheck_path "${path}")"
    local ok=1
    case "${type}" in
        f) [ -f "${p}" ] ;;
        d) [ -d "${p}" ] ;;
        x) [ -f "${p}" ] && [ -x "${p}" ] ;;
        l) [ -L "${p}" ] ;;
        S) [ -S "${p}" ] ;;
        *) [ -e "${p}" ] || [ -L "${p}" ] ;;
    esac && ok=0
    if [ "${ok}" -eq 0 ]; then
        log_ok "Path: ${desc}"
        return 0
    fi
    log_fail "Path missing: ${desc}"
    return 1
}

# check_absent_file <path> [description] — the path must NOT exist
check_absent_file() {
    local path="${1:?check_absent_file: path required}"
    local desc="${2:-${path}}"
    dry_run "check_absent_file ${path}" && return 0
    local p; p="$(fiocheck_path "${path}")"
    if [ -e "${p}" ] || [ -L "${p}" ]; then
        log_fail "Path must be absent: ${desc}"
        return 1
    fi
    log_ok "Path absent: ${desc}"
    return 0
}

# check_file_mode <path> <octal_mode> — e.g. check_file_mode /var/sota 700
check_file_mode() {
    local path="${1:?check_file_mode: path required}"
    local mode="${2:?check_file_mode: mode required}"
    dry_run "check_file_mode ${path} ${mode}" && return 0
    local p; p="$(fiocheck_path "${path}")"
    if [ ! -e "${p}" ]; then
        log_fail "Mode: ${path} — not found"
        return 1
    fi
    local actual; actual="$(stat -c '%a' "${p}" 2>/dev/null)"
    mode="${mode#0}"
    if [ "${actual}" = "${mode}" ]; then
        log_ok "Mode: ${path} = ${actual}"
        return 0
    fi
    log_fail "Mode: ${path} = ${actual:-?} — expected ${mode}"
    return 1
}

# check_file_contains <path> <ERE> [description]
check_file_contains() {
    local path="${1:?check_file_contains: path required}"
    local regex="${2:?check_file_contains: pattern required}"
    local desc="${3:-${path} matches /${regex}/}"
    dry_run "check_file_contains ${path} /${regex}/" && return 0
    local p; p="$(fiocheck_path "${path}")"
    if [ ! -r "${p}" ]; then
        log_fail "Content: ${path} — not readable"
        return 1
    fi
    if grep -qE "${regex}" "${p}" 2>/dev/null; then
        log_ok "Content: ${desc}"
        return 0
    fi
    log_fail "Content: ${desc} — no match"
    return 1
}

# check_json_values <path> <key=value ...>
# Each key must appear with the value in a flat JSON file, e.g.
#   check_json_values /usr/lib/docker/daemon.json storage-driver=overlay2
check_json_values() {
    local path="${1:?check_json_values: path required}"
    shift
    dry_run "check_json_values ${path} $*" && return 0
    local p; p="$(fiocheck_path "${path}")"
    if [ ! -r "${p}" ]; then
        log_fail "JSON: ${path} — not readable"
        return 1
    fi
    local rc=0 kv key val
    for kv in "$@"; do
        key="$(_ere_escape "${kv%%=*}")"
        val="$(_ere_escape "${kv#*=}")"
        if grep -qE "\"${key}\"[[:space:]]*:[[:space:]]*\"?${val}\"?[[:space:]]*(,|\}|$)" "${p}" 2>/dev/null; then
            log_ok "JSON: ${path} ${kv}"
        else
            log_fail "JSON: ${path} — expected ${kv}"
            rc=1
        fi
    done
    return "${rc}"
}

# check_cert_expiry <pem> [min_days] — certificate must be valid for
# min_days more days (default 0 = not expired). Needs openssl.
check_cert_expiry() {
    local pem="${1:?check_cert_expiry: path required}"
    local days="${2:-0}"
    dry_run "check_cert_expiry ${pem} ${days}d" && return 0
    local p; p="$(fiocheck_path "${pem}")"
    if [ ! -r "${p}" ]; then
        log_fail "Certificate: ${pem} — not readable"
        return 1
    fi
    if ! command -v openssl >/dev/null 2>&1; then
        log_skip "Certificate: ${pem} — openssl not available"
        return 0
    fi
    local end; end="$(openssl x509 -in "${p}" -noout -enddate 2>/dev/null | cut -d= -f2)"
    if [ -z "${end}" ]; then
        log_fail "Certificate: ${pem} — not a valid PEM certificate"
        return 1
    fi
    if openssl x509 -in "${p}" -noout -checkend $(( days * 86400 )) >/dev/null 2>&1; then
        log_ok "Certificate: ${pem} valid until ${end}"
        return 0
    fi
    if [ "${days}" -gt 0 ] && openssl x509 -in "${p}" -noout -checkend 0 >/dev/null 2>&1; then
        log_warn "Certificate: ${pem} expires within ${days} days (${end})"
        return 0
    fi
    log_fail "Certificate: ${pem} EXPIRED (${end})"
    return 1
}

# =============================================================================
#  systemd checks
#
#  Live (systemd running): systemctl is-enabled / is-active.
#  Otherwise (--root, containers): unit files and .wants/.requires links are
#  read directly, as `systemctl --root` would.
# =============================================================================

# _unit_name <name> — append .service when no unit suffix is given
_unit_name() {
    case "$1" in
        *.service|*.socket|*.path|*.timer|*.target|*.mount) printf '%s' "$1" ;;
        *) printf '%s.service' "$1" ;;
    esac
}

_unit_dirs="/etc/systemd/system /usr/lib/systemd/system /lib/systemd/system"

# _unit_file_state <unit> — print enabled|disabled|static|masked|not-found
_unit_file_state() {
    local unit="$1" d f=""
    if _systemd_running; then
        local st; st="$(systemctl is-enabled "${unit}" 2>/dev/null)"
        case "${st}" in
            "")        printf 'not-found' ;;
            enabled-runtime|alias|indirect|generated) printf 'enabled' ;;
            linked*)   printf 'enabled' ;;
            *)         printf '%s' "${st}" ;;
        esac
        return
    fi
    local masked; masked="$(fiocheck_path "/etc/systemd/system/${unit}")"
    if [ -L "${masked}" ] && [ "$(readlink "${masked}")" = "/dev/null" ]; then
        printf 'masked'
        return
    fi
    for d in ${_unit_dirs}; do
        [ -f "$(fiocheck_path "${d}/${unit}")" ] && { f="$(fiocheck_path "${d}/${unit}")"; break; }
    done
    if [ -z "${f}" ]; then
        printf 'not-found'
        return
    fi
    for d in ${_unit_dirs}; do
        local w
        for w in "$(fiocheck_path "${d}")"/*.wants/"${unit}" "$(fiocheck_path "${d}")"/*.requires/"${unit}"; do
            if [ -e "${w}" ] || [ -L "${w}" ]; then
                printf 'enabled'
                return
            fi
        done
    done
    if grep -qE '^(WantedBy|RequiredBy|Alias|Also)=' "${f}" 2>/dev/null; then
        printf 'disabled'
    else
        printf 'static'
    fi
}

# check_systemd_unit <unit> [expected]
#   expected: enabled | disabled | static | masked | absent, or alternatives
#   joined with "|" (e.g. "enabled|disabled"). Default: present and not masked
#   (warns when disabled).
# Live runs also report the active state; a failed unit is a WARN.
check_systemd_unit() {
    local unit; unit="$(_unit_name "${1:?check_systemd_unit: unit required}")"
    local expected="${2:-}"

    dry_run "check_systemd_unit ${unit}${expected:+ expected=${expected}}" && return 0
    if ! fiocheck_static && ! command -v systemctl >/dev/null 2>&1 && [ ! -d /etc/systemd/system ]; then
        log_skip "unit: ${unit} — not a systemd system"
        return 0
    fi

    local state; state="$(_unit_file_state "${unit}")"
    print_verbose "unit ${unit}: ${state}"

    if [ "${expected}" = "absent" ]; then
        if [ "${state}" = "not-found" ]; then
            log_ok "unit: ${unit} absent"
            return 0
        fi
        log_fail "unit: ${unit} must be absent (state=${state})"
        return 1
    fi
    if [ "${state}" = "not-found" ]; then
        log_fail "unit: ${unit} — unit file not found"
        return 1
    fi
    if [ "${state}" = "masked" ] && [ "${expected}" != "masked" ]; then
        log_fail "unit: ${unit} is masked"
        return 1
    fi

    local active=""
    _systemd_running && active="$(systemctl is-active "${unit}" 2>/dev/null)"
    local msg="unit: ${unit} enable=${state}${active:+ active=${active}}"

    if [ -n "${expected}" ]; then
        case "|${expected}|" in
            *"|${state}|"*) log_ok "${msg}" ;;
            *) log_fail "${msg} — expected ${expected}"; return 1 ;;
        esac
    else
        log_ok "${msg}"
        [ "${state}" = "disabled" ] && log_warn "unit: ${unit} is disabled — it will not start on boot"
    fi
    [ "${active}" = "failed" ] && log_warn "unit: ${unit} is failed — check: journalctl -u ${unit}"
    return 0
}

# check_systemd_service <name> [expected] — kept for existing profiles
check_systemd_service() { check_systemd_unit "$@"; }

# check_unit_active <unit> [expected] — live only; expected default "active"
check_unit_active() {
    local unit; unit="$(_unit_name "${1:?check_unit_active: unit required}")"
    local expected="${2:-active}"
    dry_run "check_unit_active ${unit} ${expected}" && return 0
    require_runtime "unit ${unit} active state" || return 0
    if ! _systemd_running; then
        log_skip "unit: ${unit} — systemd not running"
        return 0
    fi
    local active; active="$(systemctl is-active "${unit}" 2>/dev/null)"
    case "|${expected}|" in
        *"|${active}|"*) log_ok "unit: ${unit} active=${active}"; return 0 ;;
    esac
    log_fail "unit: ${unit} active=${active:-unknown} — expected ${expected}"
    return 1
}

# =============================================================================
#  Lib and profile discovery
# =============================================================================

# _find_libs — relative paths of every lib file, top level first
_find_libs() {
    if [ ! -d "${FIO_TEST_LIB}" ]; then
        print_fail "Lib directory not found: ${FIO_TEST_LIB}"
        return 1
    fi
    find "${FIO_TEST_LIB}" -mindepth 1 -maxdepth 1 -type f -name "*.sh" | sort \
        | sed "s|^${FIO_TEST_LIB}/||"
    find "${FIO_TEST_LIB}" -mindepth 2 -maxdepth 5 -type f -name "*.sh" | sort \
        | sed "s|^${FIO_TEST_LIB}/||"
}

# _list_lib_functions <path> <name> — the lib's functions as run targets
# (<name>:<function>)
_list_lib_functions() {
    local prefix="lib_$2_"
    grep -E '^(lib_[a-z0-9_]+)\(\)' "$1" 2>/dev/null \
        | sed 's/() *{.*//' \
        | while IFS= read -r fn; do
            case "${fn}" in
                "${prefix}"*) printf '      %s  %s\n' "$(_color_dim '·')" "$(_color_yellow "$2:${fn#"${prefix}"}")" ;;
                *)            printf '      %s  %s\n' "$(_color_dim '·')" "$(_color_yellow "$2:${fn}")" ;;
            esac
        done
}

# list_libs — lib modules grouped by directory (functions with DETAILED=1)
list_libs() {
    print_section "Libs ${FIO_TEST_LIB}  (run <lib> or <lib>:<function>)"
    if [ ! -d "${FIO_TEST_LIB}" ]; then
        print_warn "Lib directory not found: ${FIO_TEST_LIB}"
        return 0
    fi
    local tmp; tmp="$(mktemp)"
    _find_libs 2>/dev/null > "${tmp}" || true
    if [ ! -s "${tmp}" ]; then
        rm -f "${tmp}"
        print_warn "No lib modules found in: ${FIO_TEST_LIB}"
        return 0
    fi
    local prev="" group rel
    while IFS= read -r rel; do
        case "${rel}" in
            */*) group="$(printf '%s' "${rel}" | cut -d/ -f1)" ;;
            *)   group="lib" ;;
        esac
        if [ "${group}" != "${prev}" ]; then
            printf '\n  %s\n' "$(_color_bold "$(_color_cyan "${group}")")"
            prev="${group}"
        fi
        local name; name="$(basename "${rel}" .sh)"; name="${name#lib_}"
        printf '    %s  %-26s %s\n' "$(_color_dim '▸')" "$(_color_yellow "${name}")" "$(_color_dim "${rel}")"
        [ "${DETAILED}" -eq 1 ] && _list_lib_functions "${FIO_TEST_LIB}/${rel}" "${name}"
    done < "${tmp}"
    rm -f "${tmp}"
    printf '\n'
}

# _find_profiles — relative paths of every runnable profile.
# expect/ and machine/ hold data, and files named _*.sh are fragments.
_find_profiles() {
    if [ ! -d "${FIO_TEST_PROFILES}" ]; then
        print_fail "Profiles directory not found: ${FIO_TEST_PROFILES}"
        return 1
    fi
    find "${FIO_TEST_PROFILES}" -mindepth 2 -maxdepth 5 -type f -name "*.sh" \
        ! -path "*/expect/*" ! -path "*/machine/*" ! -name "_*" \
        | sort | sed "s|^${FIO_TEST_PROFILES}/||"
}

# _list_data <dir> — names of the .sh files in <dir>, space separated
_list_data() {
    [ -d "$1" ] || return 0
    find "$1" -mindepth 1 -maxdepth 1 -type f -name "*.sh" | sort \
        | sed -e 's|.*/||' -e 's|\.sh$||' | tr '\n' ' '
}

# list_profiles — profiles grouped by layer, with their expectation sets
# and machine files
list_profiles() {
    print_section "Profiles ${FIO_TEST_PROFILES}  (run <layer>/<profile>)"
    local tmp; tmp="$(mktemp)"
    _find_profiles 2>/dev/null > "${tmp}" || true
    if [ ! -s "${tmp}" ]; then
        rm -f "${tmp}"
        print_warn "No profiles found in: ${FIO_TEST_PROFILES}"
        return 0
    fi
    local prev="" group rel data
    while IFS= read -r rel; do
        group="$(printf '%s' "${rel}" | cut -d/ -f1)"
        if [ "${group}" != "${prev}" ]; then
            printf '\n  %s\n' "$(_color_bold "$(_color_cyan "${group}")")"
            data="$(_list_data "${FIO_TEST_PROFILES}/${group}/expect")"
            [ -n "${data}" ] && printf '    %s %s\n' "$(_color_dim 'expect: ')" "${data}"
            data="$(_list_data "${FIO_TEST_PROFILES}/${group}/machine")"
            [ -n "${data}" ] && printf '    %s %s\n' "$(_color_dim 'machine:')" "${data}"
            prev="${group}"
        fi
        printf '    %s  %s\n' "$(_color_dim '▸')" "$(_color_yellow "${rel%.sh}")"
    done < "${tmp}"
    rm -f "${tmp}"
    printf '\n'
}

# =============================================================================
#  Runners
# =============================================================================

# _reset_lib_env — unset every _LIB_*_LOADED guard so libs reload cleanly
_reset_lib_env() {
    local e tmp; tmp="$(mktemp)"
    set | sed -n '/^_LIB_.*_LOADED=/s/=.*//p' > "${tmp}" 2>/dev/null || true
    while IFS= read -r e; do
        unset "${e}"
    done < "${tmp}"
    rm -f "${tmp}"
}

# _abs <path> — absolute path of an existing file (no realpath on targets)
_abs() {
    local dir; dir="$(cd "$(dirname "$1")" 2>/dev/null && pwd)" || return 1
    printf '%s/%s' "${dir}" "$(basename "$1")"
}

# _resolve_lib <arg> — absolute lib path. Accepts a path, a path relative to
# the lib dir, a file name inside lib/components/, or a component name
# ("docker" -> lib_docker.sh).
_resolve_lib() {
    local arg="$1" c
    for c in "${arg}" "${FIO_TEST_LIB}/${arg}" "${FIO_TEST_LIB}/${arg}.sh" \
             "${FIO_TEST_LIB}/lib_${arg}.sh" \
             "${FIO_TEST_LIB}/components/${arg}" "${FIO_TEST_LIB}/components/${arg}.sh" \
             "${FIO_TEST_LIB}/components/lib_${arg}.sh"; do
        [ -f "${c}" ] && { _abs "${c}"; return; }
    done
    return 1
}

# _reset_counters — fresh counters and lib state for one run
_reset_counters() {
    _TEST_PASS=0; _TEST_FAIL=0; _TEST_WARN=0; _TEST_SKIP=0
    _REPORT_LINES=""
    _FIOCHECK_REQ=""
}

# _print_run_info — banner lines shared by lib and profile runs
_print_run_info() {
    [ -n "${FILTER}" ] && print_info "Filter active: showing only [$(printf '%s' "${FILTER}" | tr 'a-z' 'A-Z')] results"
    [ "${DRY_RUN}" -eq 1 ] && print_info "Dry-run active: checks are listed, not executed"
    log_info "Path: $1"
    log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    if fiocheck_static; then
        log_info "Root: ${FIOCHECK_ROOT} (static checks only)"
    else
        log_info "Host: $(uname -n)  Kernel: $(uname -r)  Arch: $(uname -m)"
    fi
    log_info "Mode: ${FIOCHECK_MODE}${EXPECT:+  Expect: ${EXPECT}}${MACHINE:+  Machine: ${MACHINE}}"
}

# _print_summary — results line, report file, exit status
_print_summary() {
    print_section "Results"
    printf '  %s  %s  %s  %s\n\n' \
        "$(_color_green  "PASS: ${_TEST_PASS}")" \
        "$(_color_red    "FAIL: ${_TEST_FAIL}")" \
        "$(_color_yellow "WARN: ${_TEST_WARN}")" \
        "$(_color_dim    "SKIP: ${_TEST_SKIP}")"
    [ -n "${REPORT_FILE}" ] && write_report "${REPORT_FILE}"
    [ "${_TEST_FAIL}" -eq 0 ]
}

# _find_data <kind> <name> — path of an expectation set or machine file.
# <name>: a file path, <layer>/<name>, or a bare name looked up in the
# profile's layer (profile runs) or in every layer (must be unique).
_find_data() {
    local kind="$1" name="$2" f hits="" n=0
    if [ -f "${name}" ]; then printf '%s' "${name}"; return 0; fi
    case "${name}" in
        */*)
            f="${FIO_TEST_PROFILES}/${name%%/*}/${kind}/${name#*/}.sh"
            [ -f "${f}" ] && { printf '%s' "${f}"; return 0; }
            return 1 ;;
    esac
    if [ -n "${FIOCHECK_PROFILE_DIR}" ]; then
        f="${FIOCHECK_PROFILE_DIR}/${kind}/${name}.sh"
        [ -f "${f}" ] && { printf '%s' "${f}"; return 0; }
        return 1
    fi
    for f in "${FIO_TEST_PROFILES}"/*/"${kind}/${name}.sh"; do
        [ -f "${f}" ] || continue
        hits="${hits} ${f}"; n=$(( n + 1 ))
    done
    [ "${n}" -eq 1 ] && { printf '%s' "${hits# }"; return 0; }
    [ "${n}" -gt 1 ] && return 2
    return 1
}

# _source_data <kind> <name> — source an expectation set or machine file
# kind: expect | machine
_source_data() {
    local kind="$1" name="$2" f rc
    [ -n "${name}" ] || return 0
    f="$(_find_data "${kind}" "${name}")"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        if [ "${rc}" -eq 2 ]; then
            print_fail "${kind} '${name}' exists in several layers — use <layer>/${name}"
        else
            print_fail "${kind} '${name}' not found"
        fi
        local avail="" d l n
        for d in "${FIO_TEST_PROFILES}"/*/"${kind}"; do
            [ -d "${d}" ] || continue
            l="$(basename "$(dirname "${d}")")"
            [ -z "${FIOCHECK_PROFILE_DIR}" ] || [ "${FIOCHECK_PROFILE_DIR}" = "$(dirname "${d}")" ] || continue
            for n in $(_list_data "${d}"); do
                avail="${avail} ${l}/${n}"
            done
        done
        [ -n "${avail# }" ] && print_info "Available: ${avail# }"
        return 1
    fi
    log_info "${kind}: $(_abs "${f}")"
    # shellcheck disable=SC1090
    . "${f}"
}

# run_lib <lib_path> <fn> — source one lib and call one of its functions
run_lib() {
    local lib_path="$1" fn="$2"
    _reset_counters
    _reset_lib_env
    FIOCHECK_PROFILE_DIR=""
    print_section "Running Lib: $(basename "${lib_path}" .sh) → ${fn}"
    _print_run_info "${lib_path}"
    _source_data machine "${MACHINE}" || return 1
    _source_data expect "${EXPECT}" || return 1

    # shellcheck disable=SC1090
    . "${lib_path}"
    if command -v "${fn}" >/dev/null 2>&1; then
        "${fn}"
    else
        log_warn "Function not found: ${fn}"
        log_info "Functions in $(basename "${lib_path}"):"
        local f tmp; tmp="$(mktemp)"
        grep -E '^lib_[a-z0-9_]+\(\)' "${lib_path}" 2>/dev/null | sed 's/() *{.*//' > "${tmp}" || true
        while IFS= read -r f; do
            log_info "  ${f}"
        done < "${tmp}"
        rm -f "${tmp}"
    fi
    _print_summary
}

# run_target <target> — run a profile, a lib, or one lib function
#   meta-foundries/full-update   profile (path, <layer>/<name>, folder name)
#   docker                       lib: lib_docker_all
#   docker:daemon_config         one function: lib_docker_daemon_config
# A name that is both a profile and a lib runs the profile.
run_target() {
    local target="${1:-}"
    if [ -z "${target}" ]; then
        printf '%s\n' "run: target required (a profile, a lib, or lib:function)" >&2
        exit 2
    fi

    local lib fn path base
    case "${target}" in
        *:*)
            lib="${target%%:*}"
            fn="${target#*:}"
            if ! path="$(_resolve_lib "${lib}")"; then
                print_fail "Lib not found: ${lib}"
                print_info "Run '$(basename "$0") list' to see the profiles and libs."
                return 1
            fi
            base="$(basename "${path}" .sh)"
            case "${fn}" in
                lib_*) ;;
                *)     fn="${base}_${fn}" ;;
            esac
            run_lib "${path}" "${fn}"
            return
            ;;
    esac

    if path="$(_resolve_profile "${target}")"; then
        load_profile "${path}"
        return
    fi
    if path="$(_resolve_lib "${target}")"; then
        run_lib "${path}" "$(basename "${path}" .sh)_all"
        return
    fi
    print_fail "Not a profile or lib: ${target}"
    print_info "Run '$(basename "$0") list' to see the profiles and libs."
    return 1
}

# _resolve_profile <arg> — absolute profile path. Accepts a path, a path
# relative to the profiles dir (with or without .sh), or a folder name
# (its first profile).
_resolve_profile() {
    local arg="$1" c
    for c in "${arg}" "${FIO_TEST_PROFILES}/${arg}" "${FIO_TEST_PROFILES}/${arg}.sh"; do
        [ -f "${c}" ] && { _abs "${c}"; return; }
    done
    [ -d "${FIO_TEST_PROFILES}/${arg}" ] || return 1
    c="$(find "${FIO_TEST_PROFILES}/${arg}" -maxdepth 1 -type f -name "*.sh" ! -name "_*" \
        | sort | head -n 1)"
    [ -n "${c}" ] && _abs "${c}"
}

# load_profile <profile>
# Sources, in order: the machine file (--machine), the expectation set
# (--expect), the profile. Profiles assign defaults with : "${VAR:=value}",
# so the precedence is environment > machine > expect > profile.
# Then calls fiocheck_pre_hook, fiocheck_run, fiocheck_post_hook when defined.
load_profile() {
    local path="$1"

    _PROFILE_LOADED="${path}"
    FIOCHECK_PROFILE_DIR="$(dirname "${path}")"
    _reset_counters
    _reset_lib_env
    unset -f fiocheck_pre_hook fiocheck_post_hook fiocheck_run 2>/dev/null || true

    print_section "Loading Profile: $(basename "${path}" .sh)"
    _print_run_info "${path}"
    _source_data machine "${MACHINE}" || return 1
    _source_data expect "${EXPECT}" || return 1

    # shellcheck disable=SC1090
    . "${path}"
    if command -v fiocheck_pre_hook >/dev/null 2>&1; then fiocheck_pre_hook; fi
    if command -v fiocheck_run >/dev/null 2>&1; then fiocheck_run; fi
    if command -v fiocheck_post_hook >/dev/null 2>&1; then fiocheck_post_hook; fi
    _FIOCHECK_REQ=""
    _print_summary
}

# =============================================================================
#  Report
# =============================================================================

# write_report [file] — plain-text report (default: fiocheck_report_<ts>.txt)
write_report() {
    local out="${1:-fiocheck_report_$(date '+%Y%m%d_%H%M%S').txt}"
    {
        printf 'Foundries Check Report — version %s\n' "${SCRIPT_VERSION}"
        printf 'Generated : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        if fiocheck_static; then
            printf 'Root      : %s (static checks)\n' "${FIOCHECK_ROOT}"
        else
            printf 'Host      : %s\n' "$(uname -n)"
            printf 'Kernel    : %s\n' "$(uname -r)"
            printf 'Arch      : %s\n' "$(uname -m)"
        fi
        printf 'Mode      : %s\n' "${FIOCHECK_MODE}"
        [ -n "${_PROFILE_LOADED}" ] && printf 'Profile   : %s\n' "${_PROFILE_LOADED}"
        [ -n "${EXPECT}" ]  && printf 'Expect    : %s\n' "${EXPECT}"
        [ -n "${MACHINE}" ] && printf 'Machine   : %s\n' "${MACHINE}"
        printf '%s\n' "$(_rule 60)"
        printf '%s\n' "${_REPORT_LINES}"
        printf '%s\n' "$(_rule 60)"
        printf 'PASS: %d   FAIL: %d   WARN: %d   SKIP: %d\n' \
            "${_TEST_PASS}" "${_TEST_FAIL}" "${_TEST_WARN}" "${_TEST_SKIP}"
    } > "${out}"
    print_ok "Report written to: ${out}"
}

# =============================================================================
#  Usage and argument parsing
# =============================================================================
usage() {
    local tool; tool="$(basename "$0")"
    cat <<EOF
$(_color_bold "${tool}") ${SCRIPT_VERSION} — Foundries.io device image checker

$(_color_bold "USAGE")
  ${tool} list [-v]
  ${tool} run <target> [OPTIONS]
  ${tool} check cmd|kconfig|lib|sysctl <args> [OPTIONS]

$(_color_bold "COMMANDS")
  list                     Profiles (with expectation sets and machines) and libs
                           -v also lists every lib function
  run <target>             Run one target:
                             <layer>/<profile>     meta-foundries/full-update
                             <lib>                 docker        (lib_docker_all)
                             <lib>:<function>      docker:daemon (lib_docker_daemon)
  check cmd <cmd...>       Commands exist
  check kconfig <SYM> [v]  Kernel option is enabled (or has value v)
  check lib <lib...>       Shared libraries are installed
  check sysctl <key> <v>   Kernel parameter has value v
  help                     Show this help

$(_color_bold "OPTIONS")  (before or after the command)
  --expect <name|file>     Expectation set: profiles/<layer>/expect/<name>.sh
  --machine <name|file>    Machine file: profiles/<layer>/machine/<name>.sh
  --root <dir>             Check an unbooted rootfs (static checks only)
  --kconfig <file>         Kernel config to check (plain or .gz)
  --mode <dev|production>  Image mode for production-only checks (default: dev)
  -r, --report <file>      Write a plain-text report
  --filter <types>         Show only these result types: ok,fail,warn,skip,info
  --warn-as-fail           Count warnings as failures
  --dry-run                List the checks without executing them
  -v, --verbose            Show the probe behind each check
  -q, --quiet              Show failures and the summary only
  --no-color               Disable ANSI colors
  --profiles-dir <dir>     Override the profiles directory (default: ./profiles)
  --lib-dir <dir>          Override the lib directory (default: ./lib)

$(_color_bold "EXAMPLES")
  ${tool} list
  ${tool} run meta-foundries/full-update --expect wrynose --machine uno-q
  ${tool} run meta-foundries/os-update --root ./rootfs --kconfig ./kernel.config
  ${tool} run meta-lmp/lmp --expect v97 -r report.txt
  ${tool} run docker:daemon_config --expect blacksail
  ${tool} check kconfig CONFIG_OVERLAY_FS y

$(_color_bold "WRITING A PROFILE")
  Libs (lib/components/) are generic: each check reads its expectation from a
  FIOCHECK_<COMPONENT>_<FIELD> variable. A profile sets its defaults before
  sourcing the libs; the environment, --machine and --expect override them.
  Checks go in fiocheck_run; fiocheck_pre_hook and fiocheck_post_hook run
  around it.

    : "\${FIOCHECK_DOCKER_VERSION:=25.0.0}"
    . "\${FIO_TEST_LIB}/components/lib_docker.sh"
    fiocheck_run() {
        fiocheck_req FR-02 "Container stack"
        lib_docker_all
    }
EOF
}

# check_cmd_kind <kind> <args...> — the `check` command
check_kind() {
    local kind="${1:-}"
    [ $# -gt 0 ] && shift
    case "${kind}" in
        cmd)     [ $# -gt 0 ] || { printf '%s\n' "check cmd: command name required" >&2; exit 2; }
                 check_cmds "$@" ;;
        kconfig) [ $# -gt 0 ] || { printf '%s\n' "check kconfig: CONFIG symbol required" >&2; exit 2; }
                 check_kconfig "$@" ;;
        lib)     [ $# -gt 0 ] || { printf '%s\n' "check lib: library name required" >&2; exit 2; }
                 check_lib_dependencies "$@" ;;
        sysctl)  [ $# -gt 1 ] || { printf '%s\n' "check sysctl: <key> <value> required" >&2; exit 2; }
                 check_sysctl "$@" ;;
        *)       printf '%s\n' "check: kind must be cmd, kconfig, lib or sysctl" >&2; exit 2 ;;
    esac
}

main() {
    local cmd="" nargs=0 a

    # Options may appear anywhere; the first word is the command and the
    # remaining words are its arguments (kept in order, NUL-free).
    while [ $# -gt 0 ]; do
        case "$1" in
            -v|--verbose)   VERBOSE=1; DETAILED=1 ;;
            -q|--quiet)     QUIET=1 ;;
            --no-color)     NO_COLOR=1 ;;
            --warn-as-fail) NO_WARNING=1 ;;
            --dry-run)      DRY_RUN=1; FIOCHECK_DRY_RUN=1 ;;
            -h|--help)      usage; exit 0 ;;
            -r|--report|--profiles-dir|--lib-dir|--filter|--expect|--machine|--root|--kconfig|--mode)
                [ -n "${2:-}" ] || { printf '%s\n' "$1 requires a value" >&2; exit 2; }
                case "$1" in
                    -r|--report)    REPORT_FILE="$2" ;;
                    --profiles-dir) FIO_TEST_PROFILES="$2" ;;
                    --lib-dir)      FIO_TEST_LIB="$2" ;;
                    --filter)       FILTER="$2"; FIO_TEST_FILTER="$2" ;;
                    --expect)       EXPECT="$2" ;;
                    --machine)      MACHINE="$2" ;;
                    --kconfig)      FIOCHECK_KCONFIG="$2" ;;
                    --root)
                        [ -d "$2" ] || { printf '%s\n' "--root: not a directory: $2" >&2; exit 2; }
                        FIOCHECK_ROOT="$(cd "$2" && pwd)" ;;
                    --mode)
                        case "$2" in dev|production) FIOCHECK_MODE="$2" ;;
                            *) printf '%s\n' "--mode must be dev or production" >&2; exit 2 ;;
                        esac ;;
                esac
                shift ;;
            -*)             print_fail "Unknown option: $1"; usage; exit 1 ;;
            *)
                if [ -z "${cmd}" ]; then
                    cmd="$1"
                else
                    nargs=$(( nargs + 1 ))
                    eval "_arg_${nargs}=\$1"
                fi ;;
        esac
        shift
    done

    # Rebuild the positional arguments of the command
    a=1
    set --
    while [ "${a}" -le "${nargs}" ]; do
        eval "set -- \"\$@\" \"\${_arg_${a}}\""
        a=$(( a + 1 ))
    done

    trap '[ -n "${_KCONFIG_TMP}" ] && rm -f "${_KCONFIG_TMP}"' EXIT

    case "${cmd}" in
        list)      list_profiles; list_libs ;;
        run)       [ $# -le 1 ] || { printf '%s\n' "run: one target at a time" >&2; exit 2; }
                   run_target "${1:-}" ;;
        check)     check_kind "$@" ;;
        help|"")   usage ;;
        *)         print_fail "Unknown command: ${cmd}"; usage; exit 1 ;;
    esac
}

main "$@"
