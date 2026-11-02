#!/bin/sh
# =============================================================================
# tests/fixtures/make-rootfs.sh <dir> <flavour> [machine] [mode]
#
# Builds a minimal unbooted rootfs carrying what a profile checks statically,
# so `fio-check.sh --root <dir>` gives deterministic results in CI.
#
#   flavour  foundries-os    Foundries OS Update (meta-foundries)
#            foundries-full  Foundries Full Update (meta-foundries)
#            lmp             LmP "lmp" distro (meta-lmp)
#   machine  hardware id written to 40-hardware-id.toml (default qemux86-64)
#   mode     dev (default): development user + empty root password
#            production:    no development user, root locked
#
# Also writes <dir>.kconfig: every CONFIG_ symbol the libs check, set to y.
# POSIX sh + busybox applets only.
# =============================================================================
set -eu

root="${1:?usage: make-rootfs.sh <dir> <flavour> [machine] [mode]}"
flavour="${2:?flavour required}"
machine="${3:-qemux86-64}"
mode="${4:-dev}"
here="$(cd "$(dirname "$0")" && pwd)"
libdir="${here}/../../lib/components"

units="${root}/usr/lib/systemd/system"
wants="${root}/etc/systemd/system/multi-user.target.wants"

mkdir -p "${root}/usr/bin" "${root}/usr/sbin" "${root}/usr/lib" "${root}/etc" \
         "${root}/var" "${units}" "${wants}"

# exe <path> — a stub executable
exe() {
    mkdir -p "$(dirname "${root}$1")"
    printf '#!/bin/sh\nexit 0\n' > "${root}$1"
    chmod 0755 "${root}$1"
}

# unit <name> [enabled|disabled|static] [extra [Unit] lines]
unit() {
    local state="${2:-enabled}"
    {
        printf '[Unit]\nDescription=%s\n' "$1"
        [ -n "${3:-}" ] && printf '%s\n' "$3"
        printf '\n[Service]\nExecStart=/bin/true\n'
        [ "${state}" != "static" ] && printf '\n[Install]\nWantedBy=multi-user.target\n'
    } > "${units}/$1"
    [ "${state}" = "enabled" ] && ln -sf "/usr/lib/systemd/system/$1" "${wants}/$1"
    return 0
}

# ---------------------------------------------------------------------------
# Platform: OTA client, fioconfig, registration, ostree, NetworkManager
# ---------------------------------------------------------------------------
exe /usr/bin/aktualizr-lite
exe /usr/bin/fioconfig
exe /usr/bin/ostree
exe /usr/bin/nmcli
exe /usr/sbin/NetworkManager
exe /usr/sbin/fio-diag.sh
: > "${root}/usr/lib/libostree-1.so.1"

mkdir -p "${root}/var/sota"
chmod 0700 "${root}/var/sota"

unit aktualizr-lite.service
unit fioconfig.service
unit fioconfig-extract.service
unit NetworkManager.service
unit ostree-remount.service static
printf '[Unit]\nDescription=fioconfig.path\n\n[Path]\nPathExists=/var/sota/sota.toml\n\n[Install]\nWantedBy=multi-user.target\n' \
    > "${units}/fioconfig.path"
ln -sf /usr/lib/systemd/system/fioconfig.path "${wants}/fioconfig.path"

share="${root}/usr/share/fioconfig"
mkdir -p "${share}/handlers" "${share}/actions"
printf '#!/bin/sh\nSOTA_CLIENT=aktualizr-lite\nsystemctl restart $SOTA_CLIENT\n' > "${share}/handlers/aktualizr-toml-update"
for h in renew-client-cert fioconfig-oneshot; do printf '#!/bin/sh\n' > "${share}/handlers/${h}"; done
for a in diag reboot; do printf '#!/bin/sh\n' > "${share}/actions/${a}"; done

case "${flavour}" in
    foundries-*)
        exe /usr/bin/fio-device-register
        mkdir -p "${root}/usr/lib/sota/conf.d"
        chmod 0700 "${root}/usr/lib/sota/conf.d"
        printf '[provision]\nprimary_ecu_hardware_id = "%s"\n' "${machine}" \
            > "${root}/usr/lib/sota/conf.d/40-hardware-id.toml"
        printf 'ID=nodistro\nNAME="OpenEmbedded"\nPRETTY_NAME="OpenEmbedded nodistro"\nLMP_FACTORY_TAG="master"\n' \
            > "${root}/etc/os-release" ;;
    lmp)
        exe /usr/bin/lmp-device-register
        printf 'ID=lmp\nNAME="Linux-microPlatform"\nPRETTY_NAME="Linux-microPlatform"\nLMP_FACTORY_TAG="main"\n' \
            > "${root}/etc/os-release" ;;
    *) echo "unknown flavour: ${flavour}" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Container stack (Full Update and LmP)
# ---------------------------------------------------------------------------
case "${flavour}" in
    foundries-full|lmp)
        for b in docker dockerd containerd runc composectl; do exe "/usr/bin/${b}"; done
        ln -sf composectl "${root}/usr/bin/aklite-apps"
        exe /usr/libexec/docker/cli-plugins/docker-compose
        unit docker.service ;;
esac
if [ "${flavour}" = "foundries-full" ]; then
    mkdir -p "${root}/usr/lib/docker"
    cat > "${root}/usr/lib/docker/daemon.json" <<'EOF'
{
  "features": {
    "containerd-snapshotter": false
  },
  "storage-driver": "overlay2",
  "max-concurrent-downloads": 3,
  "max-download-attempts": 5
}
EOF
fi

# ---------------------------------------------------------------------------
# meta-lmp only helpers
# ---------------------------------------------------------------------------
if [ "${flavour}" = "lmp" ]; then
    exe /usr/bin/compose-apps-early-start
    exe /usr/bin/compose-apps-early-start-recovery
    unit compose-apps-early-start.service
    unit compose-apps-early-start-recovery.service static
    exe /usr/bin/fio-docker-fsck
    unit fio-docker-fsck.service enabled "Before=docker.service"
    exe /usr/bin/lmp-update-hostname
    unit lmp-auto-hostname.service
fi

# ---------------------------------------------------------------------------
# Users
# ---------------------------------------------------------------------------
printf 'root:x:0:0:root:/root:/bin/sh\n' > "${root}/etc/passwd"
if [ "${mode}" = "production" ]; then
    printf 'root:!:19000:0:99999:7:::\n' > "${root}/etc/shadow"
else
    devuser="foundries"; [ "${flavour}" = "lmp" ] && devuser="fio"
    printf '%s:x:1000:1000::/home/%s:/bin/sh\n' "${devuser}" "${devuser}" >> "${root}/etc/passwd"
    printf 'root::19000:0:99999:7:::\n%s:$6$x:19000:0:99999:7:::\n' "${devuser}" > "${root}/etc/shadow"
    mkdir -p "${root}/etc/sudoers.d"
    printf '%s ALL=(ALL) ALL\n' "${devuser}" > "${root}/etc/sudoers.d/${devuser}"
fi

# ---------------------------------------------------------------------------
# Kernel config next to the rootfs: every symbol the libs check
# ---------------------------------------------------------------------------
grep -ohE 'check_kconfig CONFIG_[A-Z0-9_]+' "${libdir}"/*.sh \
    | sed 's/check_kconfig //; s/$/=y/' | sort -u > "${root}.kconfig"
