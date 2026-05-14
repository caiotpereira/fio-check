#!/usr/bin/env sh
# =============================================================================
# lib/foundries/lib_lmp_device_register.sh
#     Foundries.io Device Registration Tool (lmp-device-register)
#
# lmp-device-register is a C++ one-shot CLI tool that registers an LmP device
# with a Foundries.io Factory.  It generates an ECDSA key pair, creates a CSR,
# and exchanges it for a signed client certificate via the Foundries.io REST
# API (OAuth device-flow) or a factory-owned registration reference server.
#
# Unlike fioconfig and aktualizr-lite it is NOT a daemon — it is called once
# at provisioning time, either manually or by lmp-device-auto-register.service.
#
# Architecture
#   Binary        : /usr/bin/lmp-device-register  (C++, dynamically linked)
#   Config dir    : /etc/sota/                     (hsm, tag config files)
#   HSM config    : /etc/sota/hsm                  (optional — PKCS#11 module)
#   Tag config    : /etc/sota/tag                  (optional — update tag)
#   API token     : /etc/lmp-device-register-token (CI / auto-register)
#   Result        : /var/sota/sota.toml, client.pem, pkey.pem, root.crt
#                   (populated only AFTER successful registration)
#
# Shared libraries (from CMakeLists.txt)
#   Required  : libboost_filesystem, libboost_iostreams, libboost_program_options
#               libcurl, libglib-2.0, libssl, libcrypto
#   Optional  : libp11   (PKCS#11 / HSM support — default ON, warn if missing)
#
# Key CLI options
#   -n <name>         device name in the Factory
#   -f <factory>      factory name (only needed on first registration)
#   -a <apps>         comma-separated list of compose apps to enable
#   -T <tag>          update tag (e.g. main, devel)
#   --start-daemon=0  do not auto-start aktualizr-lite after registration
#   DEVICE_API=<url>  override default https://api.foundries.io/ota/devices/
#   PRODUCTION=1      issue a production category client certificate
#
# HSM / PKCS#11 (optional)
#   When /etc/sota/hsm is present, lmp-device-register uses libp11 to store
#   the device private key in the PKCS#11 token instead of /var/sota/pkey.pem.
#   Without HSM the key is generated in software and written to disk.
#
# Registration state
#   /var/sota/sql.db   exists only after successful registration.
#   All /var/sota/* credential files are populated post-registration — any
#   check against them is warn-only because the device may simply not have
#   been registered yet.
#
# References
#   https://github.com/foundriesio/lmp-device-register
#   https://docs.foundries.io/latest/getting-started/register-device/
#   https://docs.foundries.io/latest/reference-manual/security/factory-registration-ref.html
#   https://docs.foundries.io/latest/user-guide/lmp-device-auto-register/
#
# Sourced by profiles; never executed directly.
# =============================================================================

[ -n "${_LIB_LMP_DEVICE_REGISTER_LOADED:-}" ] && return 0
_LIB_LMP_DEVICE_REGISTER_LOADED=1

# ---------------------------------------------------------------------------
# lib_lmp_device_register_kconfig — kernel requirements
#
# lmp-device-register makes HTTPS calls to api.foundries.io (OAuth + REST)
# and needs a working IP stack.  No container or virtualisation features
# are required.
# ---------------------------------------------------------------------------
lib_lmp_device_register_kconfig() {
    check_kconfig CONFIG_NET
    check_kconfig CONFIG_INET
    check_kconfig CONFIG_IPV6         # Foundries API reachable over IPv6
    check_kconfig CONFIG_TLS          # kernel TLS offload (optional but present in LmP)
    check_kconfig CONFIG_CRYPTO       # crypto subsystem — key generation
    check_kconfig CONFIG_CRYPTO_ECDSA # ECDSA — device key pair is NIST P-256
    check_kconfig CONFIG_CRYPTO_SHA256
}

# ---------------------------------------------------------------------------
# lib_lmp_device_register_lib_check — shared library dependencies
#
# lmp-device-register is a dynamically linked C++ binary.  All libs below
# are pulled in at runtime; the binary will not start without them.
#
# libp11 is required by default (DISABLE_PKCS11=OFF in CMake) so it is
# treated as a WARNING when absent rather than a hard failure — a build
# with DISABLE_PKCS11=ON would not link it.
# ---------------------------------------------------------------------------
lib_lmp_device_register_lib_check() {
    # ── Required — Boost ────────────────────────────────────────────────────
    check_lib_dependency boost_filesystem      "libboost-filesystem-dev"
    check_lib_dependency boost_iostreams       "libboost-iostreams-dev"
    check_lib_dependency boost_program_options "libboost-program-options-dev"

    # ── Required — network and crypto ───────────────────────────────────────
    check_lib_dependency curl    "libcurl / libcurl-dev"
    check_lib_dependency ssl     "openssl / libssl-dev"
    check_lib_dependency crypto  "openssl / libssl-dev"

    # ── Required — GLib ─────────────────────────────────────────────────────
    check_lib_dependency glib-2.0 "libglib2.0-dev"

    # ── Optional — PKCS#11 / HSM support ────────────────────────────────────
    # Built with libp11 by default (DISABLE_PKCS11=OFF).
    # Absent only when the binary was compiled with -DDISABLE_PKCS11=ON.
    if check_lib_dependency p11 "libp11 / libp11-dev" 2>/dev/null; then
        log_ok "Library: libp11 present (PKCS#11 / HSM support available)"
    else
        log_warn "Library: libp11 not found — PKCS#11/HSM support unavailable (binary may have been built with DISABLE_PKCS11=ON)"
    fi
}

# ---------------------------------------------------------------------------
# lib_lmp_device_register_cmd — binary check
# ---------------------------------------------------------------------------
lib_lmp_device_register_cmd() {
    check_cmd lmp-device-register "lmp-device-register (meta-lmp / Foundries.io LmP image)"

    # openssl — used for CSR inspection and cert validation (diagnostic)
    check_cmd openssl "openssl"

    # curl — network connectivity smoke test before registration attempt
    check_cmd curl "curl / libcurl"
}

# ---------------------------------------------------------------------------
# lib_lmp_device_register_files_check — config and post-registration state
# ---------------------------------------------------------------------------
lib_lmp_device_register_files_check() {
    if [ "${TESTFW_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_lmp_device_register_files_check (dry-run: filesystem probes skipped)"
        return 0
    fi

    # ── Registration state indicator ─────────────────────────────────────────
    # /var/sota/sql.db is created by aktualizr-lite on successful registration.
    # Its absence means the device has not completed registration yet.
    log_info "Checking registration state: /var/sota/sql.db"
    if [ -f /var/sota/sql.db ]; then
        local db_size; db_size="$(stat -c '%s' /var/sota/sql.db 2>/dev/null || echo 0)"
        log_ok "Registration state: /var/sota/sql.db present (${db_size} bytes) — device is registered"
    else
        log_warn "Registration state: /var/sota/sql.db not found — device has not been registered yet"
    fi

    # ── Config directory ─────────────────────────────────────────────────────
    local sota_conf_dir="/etc/sota"
    log_info "Checking config directory: ${sota_conf_dir}"
    if [ -d "${sota_conf_dir}" ]; then
        log_ok "Config directory: ${sota_conf_dir}"
    else
        log_warn "Config directory not found: ${sota_conf_dir} — missing from image?"
    fi

    # ── HSM config file (optional) ────────────────────────────────────────────
    # /etc/sota/hsm must contain HSM_MODULE, HSM_PI, and HSM_SOPIN.
    # Absent on software-key builds — always warn, never fail.
    local hsm_conf="/etc/sota/hsm"
    log_info "Checking HSM config: ${hsm_conf}"
    if [ -f "${hsm_conf}" ]; then
        log_ok "HSM config: ${hsm_conf} present (HSM registration mode)"
        # Validate required keys are present (values deliberately not logged)
        for key in HSM_MODULE HSM_PI HSM_SOPIN; do
            if grep -q "^${key}=" "${hsm_conf}" 2>/dev/null; then
                log_ok  "  HSM config key: ${key} defined"
            else
                log_warn "  HSM config key: ${key} missing from ${hsm_conf}"
            fi
        done
        # Surface HSM module path (non-sensitive)
        local module_path
        module_path="$(grep '^HSM_MODULE=' "${hsm_conf}" 2>/dev/null \
            | cut -d= -f2 | tr -d '"' || true)"
        if [ -n "${module_path}" ]; then
            log_info "  HSM module path: ${module_path}"
            if [ -e "${module_path}" ]; then
                log_ok  "  HSM module: ${module_path} exists"
            else
                log_warn "  HSM module: ${module_path} not found on filesystem"
            fi
        fi
    else
        log_warn "HSM config not found: ${hsm_conf} — software key generation will be used (expected if no HSM)"
    fi

    # ── Tag config file (optional) ────────────────────────────────────────────
    local tag_conf="/etc/sota/tag"
    log_info "Checking tag config: ${tag_conf}"
    if [ -f "${tag_conf}" ]; then
        local tag_val; tag_val="$(cat "${tag_conf}" 2>/dev/null | tr -d '[:space:]')"
        if [ -n "${tag_val}" ]; then
            log_ok "Tag config: ${tag_conf} — tag='${tag_val}'"
        else
            log_warn "Tag config: ${tag_conf} exists but is empty"
        fi
    else
        log_warn "Tag config not found: ${tag_conf} — device will use factory default tag (expected in many setups)"
    fi

    # ── API token file (optional — used by auto-register only) ───────────────
    local token_file="/etc/lmp-device-register-token"
    log_info "Checking API token file: ${token_file}"
    if [ -f "${token_file}" ]; then
        # Token is sensitive — only confirm presence, never log its value
        log_ok "API token file: ${token_file} present (auto-register mode)"
        # Check permissions — should not be world-readable
        local perms; perms="$(stat -c '%a' "${token_file}" 2>/dev/null || true)"
        if [ -n "${perms}" ]; then
            local perms_dec
            perms_dec=$(printf '%d' "0${perms}" 2>/dev/null || echo 0)
            if [ $(( perms_dec & 4 )) -ne 0 ]; then
                log_warn "API token file: ${token_file} is world-readable (permissions ${perms}) — tighten to 0600"
            else
                log_ok "API token file: permissions ${perms} (not world-readable)"
            fi
        fi
    else
        log_warn "API token file not found: ${token_file} — manual OAuth flow will be used (expected for interactive registration)"
    fi

    # ── Post-registration credentials (all warn-only) ────────────────────────
    log_info "Checking post-registration credential files"
    for cred_file in \
        "/var/sota/sota.toml:OTA config" \
        "/var/sota/client.pem:mTLS client cert" \
        "/var/sota/root.crt:Factory root CA"; do
        local path="${cred_file%%:*}"
        local desc="${cred_file##*:}"
        if [ -f "${path}" ]; then
            log_ok "  ${desc}: ${path}"
            # Validate cert expiry for PEM files
            case "${path}" in
                *.pem|*.crt)
                    if command -v openssl >/dev/null 2>&1; then
                        if openssl x509 -in "${path}" -noout -checkend 0 >/dev/null 2>&1; then
                            local expiry
                            expiry="$(openssl x509 -in "${path}" -noout -enddate 2>/dev/null \
                                | cut -d= -f2 || true)"
                            log_ok  "    cert valid, expires: ${expiry}"
                        else
                            log_fail "    cert EXPIRED: ${path} — re-registration or cert rotation required"
                        fi
                    fi ;;
            esac
        else
            log_warn "  ${desc}: ${path} not found — device not yet registered"
        fi
    done

    # pkey.pem is only present when NOT using an HSM
    if [ -f /var/sota/pkey.pem ]; then
        log_ok "  Device private key: /var/sota/pkey.pem (software key — no HSM)"
    else
        log_warn "  Device private key: /var/sota/pkey.pem not found — key is in HSM or device not registered"
    fi
}

# ---------------------------------------------------------------------------
# lib_lmp_device_register_service — auto-register service state (optional)
#
# lmp-device-auto-register.service is a oneshot unit that calls
# lmp-device-register on first boot. It is not always present — manual
# registration workflows do not install it, so absence is warn-only.
# ---------------------------------------------------------------------------
lib_lmp_device_register_service() {
    if [ "${TESTFW_DRY_RUN:-0}" -eq 1 ]; then
        _dry_print "lib_lmp_device_register_service (dry-run: systemctl probe skipped)"
        return 0
    fi

    log_info "Checking lmp-device-auto-register service"
    if ! command -v systemctl >/dev/null 2>&1; then
        log_skip "service check: systemctl not available"
        return 0
    fi

    local unit_line
    unit_line="$(systemctl list-unit-files "lmp-device-auto-register.service" \
        --no-legend 2>/dev/null | head -1)"

    if [ -z "${unit_line}" ]; then
        log_warn "lmp-device-auto-register.service: not installed (manual registration workflow assumed)"
        return 0
    fi

    local enable_state; enable_state="$(printf '%s\n' "${unit_line}" | awk '{print $2}')"
    local active_state; active_state="$(systemctl is-active lmp-device-auto-register 2>/dev/null || true)"

    log_ok "lmp-device-auto-register.service: enable=${enable_state} active=${active_state}"

    # A failed auto-register service is important to surface
    if [ "${active_state}" = "failed" ]; then
        log_warn "lmp-device-auto-register.service: in failed state — check: journalctl -u lmp-device-auto-register"
    fi
}

# ---------------------------------------------------------------------------
# lib_lmp_device_register_all — full check suite
# ---------------------------------------------------------------------------
lib_lmp_device_register_all() {
    lib_lmp_device_register_kconfig
    lib_lmp_device_register_lib_check
    lib_lmp_device_register_cmd
    lib_lmp_device_register_files_check
    lib_lmp_device_register_service
}
