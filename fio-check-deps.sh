#!/usr/bin/env bash
# =============================================================================
# fio-check.sh  –  Foundries.io dependency checker
#
# Usage:
#   ./fio-check.sh [OPTIONS] COMMAND [ARGS]
#   ./fio-check.sh --help
# Exit codes:
#   0  all required dependencies satisfied for all selected tools
#   1  one or more required dependencies missing
# =============================================================================

#set -euo pipefail

# =============================================================================
#  Global Variables
# =============================================================================
SCRIPT_VERSION="0.0.1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_COLOR=0 #disable colored terminal
NO_WARNING=0 #force warning as an error
VERBOSE=0 #verbose mode
QUIET=0 # quiet mode for automation
DRY_RUN=0 #dry-run show the commands only
FILTER="" #options: warn | fail | "warn,fail"
DETAILED=0 #don't|do show detailed information
REPORT_FILE=""
export FIO_TEST_LIB="${SCRIPT_DIR}/lib"
export FIO_TEST_PROFILES="${SCRIPT_DIR}/profiles"
export FIO_TEST_LIB_EXTRA="${SCRIPT_DIR}/lib-extras" #to be defined
export FIO_TEST_PROFILES_EXTRA="${SCRIPT_DIR}/profiles-extras" #To be defined
export FIO_TEST_FILTER=""
export FIO_TEST_DRY_RUN=""

# =============================================================================
#  Internal Variables
# =============================================================================
# Test Result for reporting arrays and variables
declare -a _REPORT_LINES=()
_PROFILE_LOADED=""
_TEST_PASS=0
_TEST_SKIP=0
_TEST_FAIL=0

declare -a _RUNALL_PROFILES=()
declare -A _RUNALL_PASS=()
declare -A _RUNALL_FAIL=()
declare -A _RUNALL_SKIP=()

#Internal Test Variable
_FIO_TEST=0
# =============================================================================
#  Internal Terminal control
# =============================================================================

#_color <color code> < text >
_color() {
    [[ 1 -eq "${NO_COLOR}" ]] && printf '%s' "$2" && return
    printf '\033[%sm%s\033[0m' "$1" "$2"
}
#Define colors
_color_red()    { _color "0;31" "$*"; }
_color_green()  { _color "0;32" "$*"; }
_color_yellow() { _color "0;33" "$*"; }
_color_blue()   { _color "0;34" "$*"; }
_color_cyan()   { _color "0;36" "$*"; }
_color_gray()   { _color "0;37" "$*"; }
_color_bold()   { _color "1" "$*"; }
_color_dim()    { _color "2" "$*"; }

#Print Functions
print_skip()     { [[ "${QUIET}" -eq 1   ]] && return; printf ' %s %s\n' "$(_color_dim    '[SKIP]')" "$*";}
print_info()     { [[ "${QUIET}" -eq 1   ]] && return; printf ' %s %s\n' "$(_color_blue   '[INFO]')" "$*";}
print_ok()       { [[ "${QUIET}" -eq 1   ]] && return; printf ' %s %s\n' "$(_color_green  '[ OK ]')" "$*";}
print_fail()     {                                     printf ' %s %s\n' "$(_color_red    '[FAIL]')" "$*" >&2;}
print_warn()     { [[ "${QUIET}" -eq 1   ]] && return; printf ' %s %s\n' "$(_color_yellow '[WARN]')" "$*";}
print_section()  { [[ "${QUIET}" -eq 1   ]] && return; printf '\n%s\n'   "$(_color_bold "== $*  ")"; }
print_verbose()  { [[ "${VERBOSE}" -eq 1 ]] && printf '  %s %s\n' "$(_color_dim '[VERB]')" "$*" || true; }

# TEST Sector
if [[ "${_FIO_TEST}" -eq 1 ]]; then
    print_skip "SKIP"
    print_info "INFO"
    print_ok "OK"
    print_fail "ERROR"
    print_warn "WARN"
    VERBOSE=1
    print_verbose "VERBOSE"
    print_section "Section"
fi

#Report Functions
_log_report () {
    _REPORT_LINES+=("$*");
}

#_filter <filter_type> - types: ok | fail | warn | skip | info
# Return 0 (show) or 1 (supressed)
_filter(){
    local filter_t="$1"
    #No Filter
    [[ -z $"${FILTER}" ]] && return 0
    case "${filter_t}" in
        ok)   [[ "${FILTER}" == *"ok"*   ]] && return 0 ;;
        fail) [[ "${FILTER}" == *"fail"* ]] && return 0 ;;
        warn) [[ "${FILTER}" == *"warn"* ]] && return 0 ;;
        skip) [[ "${FILTER}" == *"skip"* ]] && return 0 ;;
        info) [[ "${FILTER}" == *"info"* ]] && return 0 ;;
    esac
    return 1
}


# =============================================================================
#  Terminal  and Log Queue control
#  log_<function> <text>
# =============================================================================
log_ok() {
    _log_report "[ OK ] $*"
    (( _TEST_PASS++ )) || true
    _filter ok && print_ok "$*" || true
}

log_skip() {
    _log_report "[SKIP] $*"
    (( _TEST_SKIP++ )) || true
    _filter skip && print_skip "$*" || true
}

log_fail() {
    _log_report "[FAIL] $*"
    (( _TEST_FAIL++ )) || true
    _filter fail && print_fail "$*" || true
}

log_warn() {
    if [[ ${NO_WARNING} -eq 1 ]]; then
        log_fail $1;
    else
        _log_report "[WARN] $*"
        _filter warn && print_warn "$*" || true
    fi
}

log_info() {
    _log_report "[INFO] $*"
    _filter info && print_info "$*" || true
}

#dryrun_print <description> - when --dry-run it will print [DRY] line
print_dryrun() {
    printf ' %s %s\n' "$(_color_dim '[DRY ]')" "$(_color_yellow "$*")"
}


#TEST TERMINAL SECTION
if [[ "${_FIO_TEST}" -eq 1 ]]; then
    log_ok "Test ok"
    log_skip "Skip ok"
    log_fail "Fail ok"
    log_warn "Warn OK"
    NO_WARNING=1
    log_warn "Warn disabled"
    NO_WARNING=0
    log_info "Info ok"
    print_dryrun "Dry run"
fi

# =============================================================================
#  Dependency check framework
#
# =============================================================================

#check_lib_dependecy <"library_name"> ["minimal_req_version"]
check_lib_dependency() {
    local lib="${1:?check_lib_dependency: library name required}"
    local hint=""
    local min_ver="${2:-}"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        # _dry_print "check_lib_dependency ${lib}${hint:+ (hint: ${hint})}"
         print_dryrun "check_lib_dependency ${lib}:${min_ver}"
        return 0
    fi

    local found=0
    #1 - pkg-config method - Version verification OK
    if ! command -v pkg-config & 2>/dev/null; then
        print_verbose "pkg-config --exists ${lib}"
        pkg-config --exists "${lib}" 2>/dev/null && found=1 || true

        local ver;
        ver=$(pkg-config --modversion "${lib}" 2>/dev/null)
        print_verbose "pkg-config --modversion ${lib}"

        if [[ -n "${min_ver}" ]]; then
            found=1
            if pkg-config --atleast-version="${min_ver}" "${lib}" 2>/dev/null; then
                print_verbose "pkg-config --atleast-version= ${min_ver} ${lib}"
                log_ok "Library dependency: ${lib} ${ver} (≥ ${min_ver} ✔)"
            else
                log_fail "Library dependency: ${lib} ${ver} - MIN_VERSION ≥ ${min_ver}"
                return 1
            fi
        else
            log_ok "Library dependency: ${lib} ${ver}"
        fi
    else
        log_fail "Library dependency: ${lib} ${ver} (pkg-config: ${lib} - NOT FOUND)"
        return 1
    fi
    if [[ "${found}" -eq 0 ]]; then
        print_verbose "find /lib /usr/lib /usr/local/lib /lib32 /usr/lib32 /lib64 /usr/lib64 -name ${lib}*.so.*  2>/dev/null | grep -q ."

        if find /lib \
            /usr/lib \
            /usr/local/lib \
            /lib32 \
            /usr/lib32 \
            /lib64 \
            /usr/lib64 -name "${lib}*.so.*" 2>/dev/null | grep -q .; then
                log_ok "Library dependency: ${lib}";
                #@TODO decide if this message is a warning|ok|info
                [[ -n "${min_ver}" ]] && log_skip "Skip ${lib} version ${ver} check - (cannot identify the version)";
        else
                log_fail "Library dependency: ${lib} ${ver} - NOT FOUND"
                return 1
        fi
    fi
}

#check_lib_dependencies <lib1> [lib2....]
check_lib_dependencies() {
    print_section "Library Dependencies"
    if [[ "${DRY_RUN}" -eq 1 ]]; then
         print_dryrun "check_lib_dependencies ${@}"
    fi
    local all_ok=0
    for lib in "${@}"; do
        check_lib_dependency "${lib}" || all_ok=1
    done
    return "${all_ok}"
}


#Test check lib dependency
if [[ "${_FIO_TEST}" -eq 1 ]]; then
    DRY_RUN=0
    check_lib_dependency libssl
    check_lib_dependency libssl 4.0.0
    check_lib_dependency  xsy
    check_lib_dependencies "libssl" "libssh" "openssl"
    VERBOSE=1
    check_lib_dependency libssl
    check_lib_dependency libssl 4.0.0
    check_lib_dependency xsy
    check_lib_dependencies "libssl" "libssh" "openssl"
    DRY_RUN=1
    check_lib_dependency libssl
    check_lib_dependency libssl 4.0.0
    check_lib_dependency xsy 4.0.0
    check_lib_dependencies "libssl" "libssh" "openssl"
fi

# =============================================================================
#  Sysconfig Checks
#
# =============================================================================
#check_sysctl <Kernel_parameter> <expected_value>
check_sysctl() {
    local param="${1:?check_sysctl: kernel_parameter required}"
    local expected="${2:-}"
    local val=""

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        print_dryrun "sysctl -n ${param}"
    fi
    if [[ $(command -v sysctl &>/dev/null) ]]; then
        log_fail "Cannot find sysctl."
        return 1
    fi
    val=$(sysctl -n "${param}" 2>/dev/null)
    print_verbose "sysctl -n ${param}"
    if [[ "${val}" = "${expected}" ]]; then
        log_ok "Kernel parameter: ${param} expected ${expected}, configured ${val} ✔"
    else
        log_fail "Kernel parameter: ${param} expected ${expected}, configured ${val}"
        return 1
    fi

    return 0
}
# =============================================================================
#  KConfig Checks
#
# =============================================================================


# check_kconfig <CONFIG_SYMBOL> [expected_value]
# Searches /proc/config.gz, /boot/config-$(uname -r), or /boot/config
# expected_value defaults to "y" or "m" (either means enabled)
check_kconfig() {
    local symbol="${1:?check_kconfig: CONFIG symbol required}"
    local expected="${2:-}"   # optional: "y", "m", "n", or a specific value

    # Normalise: strip leading CONFIG_ if user passed it
    symbol="${symbol#CONFIG_}"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        print_dryrun "check_kconfig CONFIG_${symbol}${expected:+ expected=${expected}}"
        return 0
    fi

    local config_file=""
    if [[ -r /proc/config.gz ]]; then
        config_file="<(zcat /proc/config.gz)"
    elif [[ -r "/boot/config-$(uname -r)" ]]; then
        config_file="/boot/config-$(uname -r)"
    elif [[ -r /boot/config ]]; then
        config_file="/boot/config"
    else
        log_skip "kconfig: CONFIG_${symbol} — no kernel config found"
        return 0
    fi

    local value
    if [[ "${config_file}" == "<(zcat /proc/config.gz)" ]]; then
        _print_verbose="zcat /proc/config.gz 2>/dev/null | grep -E "^CONFIG_${symbol}=" | cut -d= -f2"
        value=$(zcat /proc/config.gz 2>/dev/null | grep -E "^CONFIG_${symbol}=" | cut -d= -f2) || true
    else
        print_verbose="grep -E "^CONFIG_${symbol}=" "${config_file}" 2>/dev/null | cut -d= -f2"
        value=$(grep -E "^CONFIG_${symbol}=" "${config_file}" 2>/dev/null | cut -d= -f2) || true
    fi

    # Handle # CONFIG_XXX is not set
    local is_unset=0
    if [[ -z "${value}" ]]; then
        if [[ "${config_file}" == "<(zcat /proc/config.gz)" ]]; then
            print_verbose "zcat /proc/config.gz 2>/dev/null | grep -q # CONFIG_${symbol} is not set"
            zcat /proc/config.gz 2>/dev/null | grep -q "# CONFIG_${symbol} is not set" && is_unset=1 || true
        else
            print_verbose "grep -q # CONFIG_${symbol} is not set ${config_file}"
            grep -q "# CONFIG_${symbol} is not set" "${config_file}" 2>/dev/null && is_unset=1 || true
        fi
    fi

    if [[ -n "${expected}" ]]; then
        if [[ "${value}" == "${expected}" ]]; then
            log_ok  "kconfig: CONFIG_${symbol}=${value}"
        else
            log_fail "kconfig: CONFIG_${symbol} expected=${expected}, got=${value:-not set}"
            return 1
        fi
    else
        # No expected → just check it's set to y or m
        if [[ "${value}" == "y" || "${value}" == "m" ]]; then
            log_ok  "kconfig: CONFIG_${symbol}=${value}"
        elif [[ "${is_unset}" -eq 1 || -z "${value}" ]]; then
            log_fail "kconfig: CONFIG_${symbol} is not enabled"
            return 1
        else
            log_ok  "kconfig: CONFIG_${symbol}=${value}"
        fi
    fi
}

# =============================================================================
#  Command check
#
# =============================================================================
# check_cmd <command> [pkg_hint]
check_cmd() {
    local cmd="${1:?check_cmd: command name required}"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        print_dryrun "check_cmd ${cmd}"
        return 0
    fi

    #check if the command exists
    print_verbose "$(command -v "${cmd}")"
    if ! command -v "${cmd}"  &>/dev/null; then
        log_fail "Command missing: ${cmd} "
        return 1
    fi
    log_ok "Command exists: ${cmd}"

    return 0
}

# check_cmds <cmd1> [cmd2 ...]
check_cmds() {
    print_section "Command Checks"
    local all_ok=0
    for cmd in "$@"; do
        check_cmd "${cmd}" || all_ok=1
    done
    return "${all_ok}"
}

# -----------------------------------------------------------------------------
# _compare_versions <version_a> <version_b>
#
# Compares two semantic version strings (e.g. "3.10.1" vs "3.8.0").
# Returns:
#   0  -> version_a == version_b
#   1  -> version_a >  version_b
#   2  -> version_a <  version_b
# -----------------------------------------------------------------------------
_compare_versions() {
    local a="$1"
    local b="$2"

    # Split on '.' and iterate through each segment
    local IFS='.'
    local -a va=($a)
    local -a vb=($b)

    # Pad to equal length with zeros
    local max=$(( ${#va[@]} > ${#vb[@]} ? ${#va[@]} : ${#vb[@]} ))
    for (( i=0; i<max; i++ )); do
        local seg_a=$(( ${va[$i]:-0} ))
        local seg_b=$(( ${vb[$i]:-0} ))

        if (( seg_a > seg_b )); then
            return 1   # a is greater
        elif (( seg_a < seg_b )); then
            return 2   # b is greater
        fi
    done
    return 0   # equal
}

# check_cmd_version <command> <min_version> [version_flag] [version_regex]
#
# Parameters:
#   command       - The binary/command to check (e.g. "node", "python3", "git")
#   min_version   - Minimum required version string (e.g. "18.0.0")
#   version_flag  - (optional) Flag to get version output (default: "--version")
#   version_regex - (optional) Regex with ONE capture group that extracts the
#                   version number from the command output.
#                   Default: '[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?)'
#   string        - True/False , Compare the string only
#
# Returns:
#   0  - Command found and version is >= min_version
#   1  - Command not found
#   2  - Version could not be parsed
#   3  - Version is below the required minimum
#
# Examples:
#   check_cmd_version "node"    "18.0.0"
#   check_cmd_version "python3" "3.9.0"
#   check_cmd_version "git"     "2.30.0"
#   check_cmd_version "docker"  "20.0.0" "--version" 'Docker Engine - Community ([0-9]+\.[0-9]+\.[0-9]+)'
check_cmd_version() {
    local cmd="${1:?check_cmd: command name required}"
    local min_ver="${2:-}"
    local version_flag="${3:---version}"
    local version_regex="${4:-[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?)}"
    local sstring="${5:false}"

    if [[ "${DRY_RUN}" -eq 1 ]]; then
        print_dryrun "check_cmd_version ${cmd} ${min_ver} "
        return 0
    fi

    #Retrieve version output
    local raw_version
    print_verbose "${cmd} ${version_flag} 2>&1"
    raw_version=$("${cmd}" "${version_flag}" 2>&1)

    #Extract the version
    local version
    version=$(echo "${raw_version}" \
        | grep -oE "${version_regex}" \
        | head -n 1)
    # version=$(echo "${raw_version}" \
    #     | grep -oE "${version_regex}" \
    #     | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' \
    #     | head -n 1)

    # print_verbose "echo \"${raw_version}\" | grep -oE '${version_regex}' | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n 1"
    print_verbose "echo \"${raw_version}\" | grep -oE '${version_regex}' | head -n 1"

    if [[ -z "${version}" ]]; then
        log_fail "Could not parse the version from: ${cmd} ${version_flag}" >&2
        log_info "      Raw output: ${raw_version}" >&2
        return 1
    fi

    #Compare version
    if [[ ${sstring} ]]; then
        print_verbose "${version} == ${min_ver} "
        if [[ "${version}" == "${min_ver}" ]]; then
            log_ok "Command: $cmd ${version} = ${min_ver} ✔"
        else
            log_fail "Command: ${cmd} version ${version} different from ${min_ver}." >&2
            return 1
        fi
    else
        _compare_versions "${version}" "${min_ver}"
        local cmp_result=$?

        if [[  "${cmp_result}" == 2 ]]; then
            log_fail "Command: ${cmd} version ${version} - MIN_VERSION ≥ ${min_ver}." >&2
            return 1
        fi
        log_ok "Command: ${cmd} version ${version} (≥ ${min_ver} ✔)"
    fi
    return 0
}


#Test cmd_version
if [[ "${_FIO_TEST}" -eq 1 ]]; then
    VERBOSE=1
    DRY_RUN=0
    check_cmd_version "docker" "26.0.0"
    check_cmd_version "docker" "16.0.0"
    check_cmd_version "docker" "0.0"
    check_cmd_version "docker" "30.0.0"
    check_cmd_version "docker" "27.3.1"

    VERBOSE=0
    DRY_RUN=0
    check_cmd_version "docker" "26.0.0"
    check_cmd_version "docker" "16.0.0"
    check_cmd_version "docker" "0.0"
    check_cmd_version "docker" "30.0.0"
    check_cmd_version "docker" "27.3.1"
    VERBOSE=0
    DRY_RUN=1
    check_cmd_version "docker" "26.0.0"
fi

# =============================================================================
#  Systemd Verification
#
# =============================================================================
# check_systemd_service <service_name> [expected_state]
#
# Verifies a systemd service unit:
#   1. Unit file exists (systemctl list-unit-files)
#   2. Enable state  — enabled | disabled | static | masked
#   3. Active state  — active | inactive | failed
#
# expected_state  optional, one of: enabled | disabled | static | masked
#                 When supplied, the enable state must match exactly.
#                 When omitted, the check passes for any state except masked
#                 and logs a warning when the service is disabled.
#
# Examples
#   check_systemd_service docker                  # exists + not masked, warn if disabled
#   check_systemd_service ssh          enabled    # must be enabled
#   check_systemd_service bluetooth    disabled   # must be disabled
check_systemd_service() {
    local ssd="${1:check_systemd_service: name required}"
    local expected_state="${2:-}"
    # local opt="${3:-}"

    if [[ "${FIO_TEST_DRY_RUN}" -eq 1 ]]; then
        print_dryrun "check_systemd_service ${ssd}${expected_state:+ expected=${expected_state}}"
        return 0
    fi

    #Verify if the distro supports systemd
    if [[ ! $(command -v systemctl &>/dev/null) ]]; then
        log_fail "Systemd Service: ${ssd} - systemctl not available "
        return 1
    fi

    #verify if the service exists
    local service_unit;
    service_unit="$(systemctl list-unit-files "${ssd}.service" --no-legend 2>/dev/null?head -1)"

    if [[ -z "${service_unit}" ]]; then
        log_fail "service: ${ssd} - Unit file not found."
        return 1
    fi


    local enable_state;
    local active_state;
    #Check the systemd service state
    enable_state="$(awk '{print $2}' <<< "${service_unit}")"
    #Check Runtime (Active)
    active_state="$(systemctl is-active "${ssd}" 2>/dev/null || true)"
    #Report
    local report_msg="service: ${ssd} enable=${enable_state} active=${active_state}"

    #Verification with pre condition
    if [[ -n "${expected_state}" ]]; then
        if [[ "${enable_state}" == "${expected_state}" ]]; then
            log_ok "${report_msg}"
        else
            log_fail "${report_msg} - expected enable=${expected_state}"
            return 1
        fi
    else
        #No Expected state
        case "${enable_state}" in
            enabled|static)
                log_ok "${report_msg}";;
            masked)
                log_fail "${report_msg} - masked unit cannot be started.";;
            disabled)
                log_ok "${report_msg}"
                log_warn "service: ${ssd} is disabled - it will not start on boot.";;
            *)
                log_ok "${report_msg}"
        esac
    fi
    # Verify separately if the unit is inactive or failed regardless of enable state
    case "${active_state}" in
        active|activating)
            log_ok "service: ${ssd} is running.";;
        failed)
            log_warn "service: ${ssd} is in failed state - check journalctl -u ${ssd} .";;
        inactive|*)
            log_warn "service is ${ssd} is ${active_state} .";;
    esac

}

# =============================================================================
#  Profile functions - Listing and Loading
#
# =============================================================================
#list_libs - List all the libraries available at ./libs
list_libs() {
    print_section "Available Lib Modules ${FIO_TEST_LIB}"

    if [[ ! -d "${FIO_TEST_LIB}" ]]; then
        print_warn "Lib directory not found: ${FIO_TEST_LIB}"
        return 0
    fi

    local -a libs #libs array
    mapfile -t libs < <(find "${FIO_TEST_LIB}" -maxdepth 5 -name "*.sh" | sort)

    if [[ "${#libs[@]}" -eq 0 ]]; then
        print_warn "No lib modules found in: ${FIO_TEST_LIB}"
        return 0
    fi

    for lib in "${libs[@]}"; do
        local name; name="$(basename "${lib}")"
        if [[ "${DETAILED}" == 1 ]]; then
            printf ' %s  %s\n' "$(_color_bold "$(_color_cyan "${name}")")" \
                "$(_color_dim "(source \"${FIO_TEST_LIB}/${name}\")")"
            # Extract exported function names (lines starting with a lib_ function def)
            grep -E '^(lib_[a-z0-9_]+)\(\)' "${lib}" \
                | sed 's/() *{.*//' \
                | while read -r fn; do
                    printf '    %s  %s\n' "$(_color_dim '·')" "$(_color_yellow "${fn}")"
                done
        else
                printf ' %s  %s\n' "$(_color_bold "$(_color_cyan "${name}")")"
        fi
    done
    printf '\n'
}

_find_profiles() {
    if [[ ! -d "${FIO_TEST_PROFILES}" ]]; then
        print_fail "Profiles directory not found: ${FIO_TEST_PROFILES}"
        return 1
    fi
    # Each profile folder contains a .sh file whose basename matches with profile_
    find "${FIO_TEST_PROFILES}" -mindepth 1 -maxdepth 5 -type f -name "*.sh" \
        | sort \
        | sed "s|^${FIO_TEST_PROFILES}/||"
}

#list_profiles - List all profiles available in the ./profiles folder
list_profiles() {
    print_section "Available Profiles ${FIO_TEST_PROFILES}"

    local -a profiles #Create the profiles array
    mapfile -t profiles < <(_find_profiles 2>/dev/null)

    if [[ "${#profiles[@]}" -eq 0 ]]; then
        print_warn "No profiles found in: ${FIO_TEST_PROFILES}"
        return 0
    fi

    local prev_group=""
    for rel in "${profiles[@]}"; do
        local group; group="$(echo "${rel}" | cut -d/ -f1)"
        if [[ "${group}" != "${prev_group}" ]]; then
            printf '\n  %s\n' "$(_color_bold "$(_color_cyan "${group}")")"
            prev_group="${group}"
        fi
        printf '    %s  %s\n' "$(_color_dim '▸')" "$(_color_yellow "${rel}")"
    done
    printf "\n"

}




#Test list libs and profiles
if [[ "${_FIO_TEST}" -eq 1 ]]; then
    list_libs
    DETAILED=1
    list_libs
    DETAILED=0
    list_profiles
fi

# =============================================================================
#  Environment Setup
#
# =============================================================================

#_reset_lib_env - Bash sanitization - unset every _LIB_*LOADED
# guard currently set in the environment so a fresh profile run
# in run-all gets a clean lib state.
# compgen discovers any variable matching the naming convention,
# so new lib modules are picked up automatically.
_reset_lib_env(){
    local e
    while IFS= read -r e; do
        unset "${e}"
    done < <(compgen -v | grep -E '^_LIB_.+_LOADED$')
}

#_resolve_profile <arg> - echo the absolute path or return 1
_resolve_profile() {
    local arg="$1"
    if [[ -f "${arg}" ]]; then
        realpath "${arg}"
        return 0
    fi
    if [[ -f "${FIO_TEST_PROFILES/${arg}}" ]]; then
        realpath "${FIO_TEST_PROFILES/${arg}}"
        return 0
    fi
    local candidate
    candidate="$(find "${FIO_TEST_PROFILES}/${arg}" -maxdepth 5 -name "*.sh" 2>/dev/null | sort | head -1)"
    if [[ -n "${candidate}" ]]; then
        realpath "${candidate}"
        return 0
    fi
    return 1
}

#load_profile <relative_or_absolute_path>
load_profile() {
    local profile_arg="${1:?load_profile: profile path required}"
    local profile_path; profile_path="$(_resolve_profile "${profile_arg}")"

    if [[ ! -f "${profile_path}" ]]; then
        print_fail "Profile not found: ${profile_path}"
        print_info "Run '$(basename "$0") list' to see available profiles."
        return 1
    fi

    #State and counter cleanup
    _PROFILE_LOADED="${profile_path}"
    _TEST_PASS=0
    _TEST_FAIL=0
    _TEST_SKIP=0

    # Undefine any hook left by a previous profile
    unset -f fiocheck_pre_hook fiocheck_post_hook 2>/dev/null || true
    _reset_lib_env

    [[ -n "${FILTER}"   ]] && print_info "Filter active: showing only [${FILTER^^}] results"
    [[ "${DRY_RUN}" -eq 1 ]] && print_info "Dry-run Active: check will be listed but not executed."

    print_section "Loading Profile: $(basename "${profile_path}" .sh)"
    log_info "Path: ${profile_path}"
    log_info "Date: $(date '+%Y-%m-%d %H:%M:%S')"
    log_info "Host: $(uname -n) Kernel: $(uname -r ) Arch: $(uname -m)"

    #Source the profile in a set +e context to accumulate the individual failures
    #The profile may define fiocheck_pre_hook / fiocheck_pos_hook;
    #If so they are called from inside the profile itself
    set +e
    source "${profile_path}"
    set -e

    #Print Summary Table
    print_section "Results"
    printf '  %s  %s  %s \n\n' \
        "$(_color_green "PASS: ${_TEST_PASS}")" \
        "$(_color_red   "FAIL: ${_TEST_FAIL}")" \
        "$(_color_dim   "SKIP: ${_TEST_SKIP}")"

    #Print Report Log
    if [[ -n "${REPORT_FILE}" ]]; then
        write_report "${REPORT_FILE}"
    fi
    [[ "${_TEST_FAIL}" -eq 0 ]]
}

# run_all — discover and run every profile; print a combined summary table
run_all() {
    local -a all_profiles
    mapfile -t all_profiles < <(_find_profiles 2>/dev/null)

    if [[ "${#all_profiles[@]}" -eq 0 ]]; then
        print_warn "No profiles found in: ${PROFILES_DIR}"
        return 0
    fi

    local _orig_report="${REPORT_FILE}"
    local _any_fail=0

    print_section "Run All — ${#all_profiles[@]} profile(s)"

    for rel in "${all_profiles[@]}"; do
        local pname; pname="${rel%.sh}"
        printf '\n'
        print_section "▶ ${pname}"

        # Per-profile report file when -r was given (append profile name)
        if [[ -n "${_orig_report}" ]]; then
            REPORT_FILE="${_orig_report%.txt}_${pname//\//_}.txt"
        fi

        # Run and capture outcome; don't let a failing profile abort the loop
        if load_profile "${rel}" 2>&1; then
            _RUNALL_PASS["${rel}"]="${_TEST_PASS}"
            _RUNALL_FAIL["${rel}"]=0
            _RUNALL_SKIP["${rel}"]="${_TEST_SKIP}"
        else
            _RUNALL_PASS["${rel}"]="${_TEST_PASS}"
            _RUNALL_FAIL["${rel}"]="${_TEST_FAIL}"
            _RUNALL_SKIP["${rel}"]="${_TEST_SKIP}"
            _any_fail=1
        fi
        _RUNALL_PROFILES+=("${rel}")
    done

    #Create the Summary Table
    REPORT_FILE="${_orig_report}"
    print_section "Run All — Summary"
    local col_w=48
    printf '  %-*s  %s  %s  %s\n' "${col_w}" "Profile" \
        "$(_color_green  'PASS')" "$(_color_red 'FAIL')" "$(_color_dim 'SKIP')"
    printf '  %s\n' "$(printf '%.0s─' $(seq 1 $(( col_w + 22 ))))"

    local total_pass=0 total_fail=0 total_skip=0
    for rel in "${_RUNALL_PROFILES[@]}"; do
        local p="${_RUNALL_PASS[${rel}]:-0}"
        local f="${_RUNALL_FAIL[${rel}]:-0}"
        local s="${_RUNALL_SKIP[${rel}]:-0}"
        (( total_pass += p )) || true
        (( total_fail += f )) || true
        (( total_skip += s )) || true

        local status
        if [[ "${f}" -gt 0 ]]; then
            status="$(_color_red    '✗ FAIL')"
        else
            status="$(_color_green  '✓ PASS')"
        fi
        printf '  %-*s  %s  p:%-4d f:%-4d s:%-4d\n' \
            "${col_w}" "${rel%.sh}" "${status}" "${p}" "${f}" "${s}"
    done

    printf '  %s\n' "$(printf '%.0s─' $(seq 1 $(( col_w + 22 ))))"
    printf '  %-*s       %s  %s  %s\n\n' "${col_w}" "TOTAL" \
        "$(_color_green  "p:${total_pass}")" \
        "$(_color_red    "f:${total_fail}")" \
        "$(_color_dim    "s:${total_skip}")"

    return "${_any_fail}"
}

# =============================================================================
#  Report Creation
#
# =============================================================================

#write_report [file] - defaults to fiocheck_report_<timestamp>.txt
write_report(){
    local out="${1:fiocheck_report_$(date '+%Y%m%d_%H%M%S')}"

    {
        printf 'Foundries Check Report — version %s\n' "${SCRIPT_VERSION}"
        printf 'Generated : %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
        printf 'Host      : %s\n' "$(uname -n)"
        printf 'Kernel    : %s\n' "$(uname -r)"
        printf 'Arch      : %s\n' "$(uname -m)"
        [[ -n "${_PROFILE_LOADED}" ]] && printf 'Profile   : %s\n' "${_PROFILE_LOADED}"
        printf '%s\n' "$(printf '%.0s─' {1..60})"
        for line in "${_REPORT_LINES[@]}"; do
            printf '%s\n' "${line}"
        done
        printf '%s\n' "$(printf '%.0s─' {1..60})"
        printf 'PASS: %d   FAIL: %d   SKIP: %d\n' "${_TEST_PASS}" "${_TEST_FAIL}" "${_TEST_SKIP}"
    } > "${out}"

    print_ok "Report written to: ${out}"
}

# =============================================================================
#  Argument Parsing
#
# =============================================================================
usage() {
    local tool="$(basename $0)"
    cat <<EOF
$(_color_bold "${tool}") ${SCRIPT_VERSION} — Embedded Linux Test Framework

$(_color_bold "USAGE")
  $(basename "$0") [OPTIONS] COMMAND [ARGS]

$(_color_bold "COMMANDS")
  list-profile             List all available profiles
  list-libs                List lib modules and their exported functions
  load <profile>           Load and run a profile (.sh path or folder name)
  run-all                  Run every profile and print a combined summary
  check-deps <lib...>      Check shared library dependencies
  check-kconfig <SYM> [v] Check a kernel CONFIG symbol (optional expected value)
  check-cmd <cmd...>       Check that commands exist on PATH
  report [file]            Write accumulated results to a plain-text file
  help                     Show this help

$(_color_bold "OPTIONS")
  -v, --verbose            Extra output
  -q, --quiet              Suppress info output
  -r, --report <file>      Auto-write report after load / per-profile in run-all
  --filter <types>         Show only matching result types (comma-separated)
                           Types: fail, warn   e.g. --filter fail,warn
  --dry-run                List what each check would do without executing it
  --no-color               Disable ANSI colors
  --profiles-dir <dir>     Override profiles directory (default: ./profiles)
  --lib-dir <dir>          Override lib directory      (default: ./lib)

$(_color_bold "EXAMPLES")
  ${tool} list-profiles
  ${tool} list-libs
  ${tool} load secure_device/tpm/tpm.sh
  ${tool} run-all
  ${tool} --filter fail run-all
  ${tool} --filter fail,warn load secure_device/composite
  ${tool} -r results.txt load secure_device/armv8/armv8.sh
  ${tool} check-kconfig CONFIG_SECURITY_SELINUX y
  ${tool} --dry-run load secure_device/composite
  ${tool} --dry-run run-all

$(_color_bold "HOOKS  (fiocheck_pre_hook / fiocheck_post_hook)")
  Any profile may define these two optional Bash functions.
  They are called before / after the profile check body.
  See profiles/examples/custom_hooks/custom_hooks.sh for a full example.

    fiocheck_pre_hook()  { log_info "starting..."; MY_TS=\$(date +%s); }
    fiocheck_post_hook() { log_info "done in \$(( \$(date +%s) - MY_TS ))s"; }

$(_color_bold "WRITING A PROFILE")
  source "\${FIO_TEST_LIB}/tpm.sh"
  source "\${FIO_TEST_LIB}/docker.sh"

  print_section "My Checks"
  lib_tpm_all
  lib_docker

  Each lib module exposes granular functions AND a lib_<n>_all wrapper.
  Modules are guard-loaded — safe to source multiple times across profiles.
EOF
}

main() {
    local cmd=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose)       VERBOSE=1 ;;
            -q|--quiet)         QUIET=1 ;;
            --no-color)         NO_COLOR=1 ;;
            -r|--report)        REPORT_FILE="${2:?--report requires a filename}"; shift ;;
            --profiles-dir)     FIO_TEST_PROFILES="${2:?--profiles-dir requires a path}"; shift ;;
            --lib-dir)          FIO_TEST_LIB="${2:?--lib-dir requires a path}"; export FIO_TEST_LIB; shift ;;
            --filter)
                FILTER="${2:?--filter requires a value (e.g. fail,warn)}"
                export FIO_TEST_FILTER="${FILTER}"
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                export FIO_TEST_DRY_RUN=1
                ;;
            list-profiles|list-libs|load|run-all|check-deps|check-kconfig|check-cmd|report|help)
                cmd="$1"; shift; break ;;
            -h|--help)          usage; exit 0 ;;
            *)  print_fail "Unknown option: $1"; usage; exit 1 ;;
        esac
        shift
    done

    case "${cmd}" in
        list-profiles) list_profiles ;;
        list-libs)     list_libs ;;
        load)          load_profile "$@" ;;
        run-all)       run_all ;;
        check-deps)    check_lib_dependencies "$@" ;;
        check-kconfig) check_kconfig "$@" ;;
        check-cmd)     check_cmds "$@" ;;
        report)        write_report "$@" ;;
        help|"")       usage ;;
        *)             print_fail "Unknown command: ${cmd}"; usage; exit 1 ;;
    esac
}

main "$@"