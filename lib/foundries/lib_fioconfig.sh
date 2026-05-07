#!/usr/bin/env bash
# =============================================================================
# lib/foundries/lib_fioconfig.sh — Foundries.io Configuration Daemon (fioconfig)
#
# fioconfig is a Go daemon that polls the Foundries.io device gateway every
# 5 minutes for configuration updates. Device-specific values are encrypted
# with ECIES (go-ecies / P-256) using the device's mTLS key pair.
#
# Architecture
#   Binary       : /usr/bin/fioconfig  (statically linked Go, no .so deps)
#   Handlers     : /usr/share/fioconfig/handlers/
#   Daemon config: /etc/default/fioconfig       (DAEMON_INTERVAL etc.)
#   Persistent   : /var/sota/config.encrypted   (encrypted config blob)
#   Runtime      : /var/run/secrets/<name>       (tmpfs — boot-time extract)
#   mTLS creds   : /var/sota/client.pem + client.key  (or HSM PKCS#11 slot)
#   Root CA      : /var/sota/factory_ca.pem
#   OTA config   : /var/sota/sota.toml          (shared with aktualizr-lite)
#
# HSM / PKCS#11 (optional)
#   When a hardware security module is present, fioconfig uses libp11 via the
#   CGo transport layer.  The PKCS#11 module path and slot PIN are stored in
#   /var/sota/sota.toml ([tls] section).
#
# References
#   https://github.com/foundriesio/fioconfig
#   https://docs.foundries.io/latest/reference-manual/ota/fioconfig.html
#   https://docs.foundries.io/latest/reference-manual/security/secure-elements/
#
# Sourced by profiles; never executed directly.
# =============================================================================
 
[[ -n "${_LIB_FIOCONFIG_LOADED:-}" ]] && return 0
_LIB_FIOCONFIG_LOADED=1
 
# ---------------------------------------------------------------------------
# lib_fioconfig_kconfig — kernel requirements
#
# fioconfig makes outbound HTTPS connections to the device gateway and
# extracts secrets into a tmpfs mount at boot.
# ---------------------------------------------------------------------------
lib_fioconfig_kconfig() {
    # TLS — kernel TLS offload (optional but present in LmP kernels)
    check_kconfig CONFIG_TLS
    # tmpfs — /var/run/secrets is a tmpfs mount populated at boot
    check_kconfig CONFIG_TMPFS
    # Unix domain sockets — used by internal IPC and systemd socket activation
    check_kconfig CONFIG_UNIX
}

# ---------------------------------------------------------------------------
# lib_fioconfig_lib_check — shared library dependencies
#
# fioconfig itself is a statically linked Go binary and has no direct .so
# dependencies at runtime.  However:
#
#   - The CGo PKCS#11 transport (used when an HSM is configured) links
#     against libp11 at build time; on LmP this is a runtime dep when
#     the binary is built with CGo enabled.
#   - libp11 itself pulls in libdl (for dlopen of the PKCS#11 module).
#   - Some LmP builds include the softhsm2 or opensc PKCS#11 module.
#
# All checks here are non-fatal (log_warn on missing) because a pure-software
# deployment without an HSM has no library dependencies at all.
# ---------------------------------------------------------------------------
lib_fioconfig_lib_check() {
    # libp11 — PKCS#11 engine bridge (needed only when HSM is configured)
    if check_lib_dependency p11 "libp11 / libp11-dev" 2>/dev/null; then
        log_ok  "Library: libp11 (PKCS#11 HSM support)"
    else
        log_warn "Library: libp11 not found — HSM/PKCS#11 support will be unavailable"
    fi

    # libdl — required by libp11 to dlopen the PKCS#11 module at runtime
    check_lib_dependency dl "libc / glibc"

    # libcrypto / openssl — used by the TLS transport layer
    check_lib_dependency crypto "openssl / libssl-dev"
    check_lib_dependency ssl    "openssl / libssl-dev"
}

# ---------------------------------------------------------------------------
# lib_fioconfig_cmd — binary and tooling checks
# ---------------------------------------------------------------------------
lib_fioconfig_cmd() {
    # Main daemon binary
    check_cmd fioconfig "fioconfig (meta-lmp / Foundries.io LmP image)"

    # pkcs11-tool — diagnostics for HSM slot and token management
    # optional — only needed when HSM is configured
    if ! command -v pkcs11-tool &>/dev/null; then
        log_warn "Command: pkcs11-tool not found — HSM diagnostics unavailable (install opensc)"
    else
        log_ok "Command: pkcs11-tool ($(command -v pkcs11-tool))"
    fi

    # p11tool — GnuTLS PKCS#11 token listing (optional diagnostic)
    if command -v p11tool &>/dev/null; then
        log_ok "Command: p11tool (optional PKCS#11 diagnostic)"
    fi

    # openssl — certificate validation and mTLS credential inspection
    check_cmd openssl "openssl"
}

# ---------------------------------------------------------------------------
# lib_fioconfig_files_check — runtime paths and file checks
# ---------------------------------------------------------------------------
lib_fioconfig_files_check() {
    if [[ "${TESTFW_DRY_RUN:-0}" -eq 1 ]]; then
        _dry_print "lib_fioconfig_files_check (dry-run: filesystem probes skipped)"
        return 0
    fi

    # ── Daemon configuration ────────────────────────────────────────────────
    local daemon_conf="/etc/default/fioconfig"
    log_info "Checking daemon config: ${daemon_conf}"
    if [[ -f "${daemon_conf}" ]]; then
        log_ok "Daemon config: ${daemon_conf}"
        # Surface the poll interval if configured
        local interval
        interval="$(grep -E '^DAEMON_INTERVAL=' "${daemon_conf}" 2>/dev/null \
            | cut -d= -f2 | tr -d '"' || true)"
        [[ -n "${interval}" ]] && log_info "  DAEMON_INTERVAL=${interval}s"
    else
        log_warn "Daemon config not found: ${daemon_conf} — default 300s polling interval in use"
    fi

    # ── OTA shared config ───────────────────────────────────────────────────
    local sota_toml="/var/sota/sota.toml"
    log_info "Checking OTA config: ${sota_toml}"
    if [[ -f "${sota_toml}" ]]; then
        log_ok "OTA config: ${sota_toml}"
        # Check for PKCS#11 module path — indicates HSM is configured
        local pkcs11_module
        pkcs11_module="$(grep -E 'tls_pkcs11_module|pkcs11' "${sota_toml}" 2>/dev/null \
            | head -1 || true)"
        if [[ -n "${pkcs11_module}" ]]; then
            log_ok "  HSM/PKCS#11 module configured in sota.toml"
            log_info "  ${pkcs11_module}"
        else
            log_info "  No HSM/PKCS#11 entry in sota.toml (software key in use)"
        fi
    else
        log_warn "OTA config not found: ${sota_toml} — /var/sota not populated yet (device not registered?)"
        return 0
    fi

    # ── mTLS credentials ────────────────────────────────────────────────────
    local client_pem="/var/sota/client.pem"
    local factory_ca="/var/sota/factory_ca.pem"

    log_info "Checking mTLS client certificate: ${client_pem}"
    if [[ -f "${client_pem}" ]]; then
        log_ok "mTLS client cert: ${client_pem}"
        # Validate cert is not expired
        if command -v openssl &>/dev/null; then
            if openssl x509 -in "${client_pem}" -noout -checkend 0 &>/dev/null; then
                local expiry
                expiry="$(openssl x509 -in "${client_pem}" -noout -enddate 2>/dev/null \
                    | cut -d= -f2 || true)"
                log_ok  "  mTLS cert valid, expires: ${expiry}"
            else
                log_fail "  mTLS cert has EXPIRED — device will fail to connect to gateway"
            fi
        fi
    else
        # Client key may be in HSM — not necessarily on disk
        log_warn "mTLS client cert not found at ${client_pem} — key may be in HSM"
    fi

    log_info "Checking factory root CA: ${factory_ca}"
    if [[ -f "${factory_ca}" ]]; then
        log_ok "Factory root CA: ${factory_ca}"
    else
        log_warn "Factory root CA not found: ${factory_ca} — /var/sota not populated yet (device not registered?)"
    fi

    # ── Persistent encrypted config ─────────────────────────────────────────
    local config_encrypted="/var/sota/config.encrypted"
    log_info "Checking encrypted config store: ${config_encrypted}"
    if [[ -f "${config_encrypted}" ]]; then
        local size_b; size_b="$(stat -c '%s' "${config_encrypted}" 2>/dev/null || echo 0)"
        log_ok "Encrypted config: ${config_encrypted} (${size_b} bytes)"
    else
        log_warn "Encrypted config not found: ${config_encrypted} — fioconfig has not synced yet"
    fi

    # ── Runtime secrets tmpfs ────────────────────────────────────────────────
    local secrets_dir="/var/run/secrets"
    log_info "Checking secrets tmpfs: ${secrets_dir}"
    if mountpoint -q "${secrets_dir}" 2>/dev/null; then
        local secret_count
        secret_count="$(find "${secrets_dir}" -maxdepth 1 -type f 2>/dev/null | wc -l)"
        log_ok "Secrets tmpfs: ${secrets_dir} is mounted (${secret_count} file(s))"
    elif [[ -d "${secrets_dir}" ]]; then
        log_warn "Secrets dir exists but is not a tmpfs mount: ${secrets_dir}"
    else
        log_warn "Secrets dir not found: ${secrets_dir} — may not have been created yet"
    fi

    # ── Handlers directory ───────────────────────────────────────────────────
    local handlers_dir="/usr/share/fioconfig/handlers"
    log_info "Checking handlers directory: ${handlers_dir}"
    if [[ -d "${handlers_dir}" ]]; then
        local handler_count
        handler_count="$(find "${handlers_dir}" -maxdepth 1 -type f 2>/dev/null | wc -l)"
        log_ok "Handlers dir: ${handlers_dir} (${handler_count} handler(s))"
        # Warn if the cert renewal handler is absent (required for cert rotation)
        if [[ -f "${handlers_dir}/renew-client-cert" ]]; then
            log_ok "  Handler: renew-client-cert (cert rotation support present)"
        else
            log_warn "  Handler: renew-client-cert not found — certificate rotation unavailable"
        fi
    else
        log_warn "Handlers dir not found: ${handlers_dir}"
    fi
}

# ---------------------------------------------------------------------------
# lib_fioconfig_service — systemd service state check
# ---------------------------------------------------------------------------
lib_fioconfig_service() {
    check_systemd_service "fioconfig" "enabled"
}

# ---------------------------------------------------------------------------
# lib_fioconfig_all — full fioconfig check suite
# ---------------------------------------------------------------------------
lib_fioconfig_all() {
    lib_fioconfig_kconfig
    lib_fioconfig_lib_check
    lib_fioconfig_cmd
    lib_fioconfig_files_check
    lib_fioconfig_service
}