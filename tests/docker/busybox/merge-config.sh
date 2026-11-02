#!/bin/sh
# =============================================================================
# merge-config.sh <cfg_dir> <variant> — print a busybox .config on stdout
#
# Starts from the OE-core defconfig and applies the config fragments the
# target build applies, in the same order:
#   oe   OE-core defconfig + OE-core fragments (meta-foundries / nodistro)
#   lmp  oe + the meta-lmp fragments (LmP distro images)
# A fragment line replaces any earlier setting of the same CONFIG_ symbol.
# CONFIG_STATIC is forced on so the binary runs in a scratch image.
# =============================================================================
set -eu

cfg_dir="${1:?cfg dir required}"
variant="${2:-oe}"

fragments="getopts longopts sha1sum sha256sum unicode rev pgrep resize \
login-utilities mount-via-label mkdosfs fdisk-gpt musl"

config="$(mktemp)"
trap 'rm -f "${config}" "${config}.new"' EXIT
cp "${cfg_dir}/oe/defconfig" "${config}"

# apply <fragment_file>
apply() {
    while IFS= read -r line; do
        sym="$(printf '%s\n' "${line}" | sed -n -e 's/^\(CONFIG_[A-Za-z0-9_]*\)=.*/\1/p' \
                                                -e 's/^# \(CONFIG_[A-Za-z0-9_]*\) is not set.*/\1/p')"
        [ -n "${sym}" ] || continue
        grep -v -e "^${sym}=" -e "^# ${sym} is not set" "${config}" > "${config}.new" || true
        printf '%s\n' "${line}" >> "${config}.new"
        mv "${config}.new" "${config}"
    done < "$1"
}

for f in ${fragments}; do
    apply "${cfg_dir}/oe/${f}.cfg"
done

if [ "${variant}" = "lmp" ]; then
    for f in less shell utils removed; do
        apply "${cfg_dir}/lmp/${f}.cfg"
    done
fi

printf 'CONFIG_STATIC=y\n' > "${config}.static"
apply "${config}.static"
rm -f "${config}.static"

cat "${config}"
