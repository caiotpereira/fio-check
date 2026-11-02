# =============================================================================
# Machine: qemuarm64-secureboot — meta-foundries ci/qemuarm64-secureboot.yml
# The distro (and OSTREE_OSNAME) is the developer's choice: set
# FIOCHECK_OSTREE_OSNAME to have the stateroot checked.
# =============================================================================

# aktualizr-lite installs /usr/lib/sota/conf.d/40-hardware-id.toml = MACHINE
: "${FIOCHECK_AKLITE_HARDWARE_ID:=qemuarm64-secureboot}"
