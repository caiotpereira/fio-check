#!/usr/bin/env sh
# =============================================================================
# lib/components/lib_device_register.sh — device registration tool
#
# Same upstream (github.com/foundriesio/lmp-device-register), two names:
#   meta-lmp        /usr/bin/lmp-device-register
#   meta-foundries  /usr/bin/fio-device-register (D-18: the lmp- name is gone)
# Registration writes the client identity under /var/sota; sota.toml names
# the files (tls_cacert_path, tls_clientcert_path, tls_pkey_path).
# Unattended registration (meta-lmp lmp-device-auto-register) reads an API
# token file, installed 0600.
#
# Expectations
#   FIOCHECK_REGISTER_BIN          registration binary (default fio-device-register)
#   FIOCHECK_REGISTER_ABSENT_BINS  binaries that must not be installed
#   FIOCHECK_REGISTER_AUTO_UNIT    auto-register unit (empty: not expected)
#   FIOCHECK_REGISTER_TOKEN_FILE   API token file (empty: not expected)
#   FIOCHECK_CERT_MIN_DAYS         warn when the client certificate expires
#                                  within this many days (default 30)
#
# Sourced by profiles and run-lib; never executed directly.
# =============================================================================

[ -n "${_LIB_DEVICE_REGISTER_LOADED:-}" ] && return 0
_LIB_DEVICE_REGISTER_LOADED=1

: "${FIOCHECK_REGISTER_BIN:=fio-device-register}"
: "${FIOCHECK_CERT_MIN_DAYS:=30}"

lib_device_register_cmd() {
    local rc=0
    check_cmd "${FIOCHECK_REGISTER_BIN}" || rc=1
    # shellcheck disable=SC2086
    [ -n "${FIOCHECK_REGISTER_ABSENT_BINS:-}" ] && { check_absent_cmd ${FIOCHECK_REGISTER_ABSENT_BINS} || rc=1; }
    return "${rc}"
}

# ---------------------------------------------------------------------------
# Unattended registration: unit and token file (FR-11 token protection)
# ---------------------------------------------------------------------------
lib_device_register_auto() {
    local rc=0
    if [ -n "${FIOCHECK_REGISTER_AUTO_UNIT:-}" ]; then
        # The unit disables itself after a successful registration
        check_systemd_unit "${FIOCHECK_REGISTER_AUTO_UNIT}" "enabled|disabled" || rc=1
    fi
    local token="${FIOCHECK_REGISTER_TOKEN_FILE:-}"
    [ -n "${token}" ] || return "${rc}"
    dry_run "token file ${token}" && return "${rc}"
    local p; p="$(fiocheck_path "${token}")"
    if [ ! -f "${p}" ]; then
        log_info "API token file: ${token} absent"
        return "${rc}"
    fi
    check_file_mode "${token}" 600 || rc=1
    if fiocheck_production && [ -s "${p}" ]; then
        log_fail "API token file: ${token} is not empty in a production image"
        rc=1
    fi
    return "${rc}"
}

# _sota_toml_path <key> — value of <key> in /var/sota/sota.toml
_sota_toml_path() {
    grep -E "^[[:space:]]*$1[[:space:]]*=" "$(fiocheck_path /var/sota/sota.toml)" 2>/dev/null \
        | head -n 1 | cut -d= -f2- | tr -d ' "'
}

# ---------------------------------------------------------------------------
# Registered identity — the files sota.toml names exist; certs not expired
# ---------------------------------------------------------------------------
lib_device_register_identity() {
    dry_run "lib_device_register_identity (sota.toml credentials)" && return 0
    if ! fiocheck_registered; then
        log_info "Registration: /var/sota/sota.toml absent — device not registered"
        return 0
    fi
    log_ok "Registration: /var/sota/sota.toml present"
    local rc=0 key path
    for key in tls_cacert_path tls_clientcert_path tls_pkey_path; do
        path="$(_sota_toml_path "${key}")"
        if [ -z "${path}" ]; then
            log_info "Registration: ${key} not set in sota.toml (PKCS#11 or default path)"
            continue
        fi
        check_file "${path}" f "${key} = ${path}" || { rc=1; continue; }
        case "${key}" in
            tls_cacert_path)     check_cert_expiry "${path}" || rc=1 ;;
            tls_clientcert_path) check_cert_expiry "${path}" "${FIOCHECK_CERT_MIN_DAYS}" || rc=1 ;;
        esac
    done
    [ -f "$(fiocheck_path /var/sota/pkey.pem)" ] && check_file_mode /var/sota/pkey.pem 600
    return "${rc}"
}

lib_device_register_all() {
    lib_device_register_cmd
    lib_device_register_auto
    lib_device_register_identity
}
