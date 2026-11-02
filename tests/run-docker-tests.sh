#!/bin/sh
# =============================================================================
# tests/run-docker-tests.sh — run test_fio_check.sh across target shells
#
# Usage:
#   tests/run-docker-tests.sh [-v] [target ...]
#
# Targets (default: all):
#   busybox-oe   scratch image, static busybox with the OE-core config
#                (meta-foundries / nodistro userland, GPLv3-free)
#   busybox-lmp  as busybox-oe plus the meta-lmp busybox fragments
#   bash         Debian, fio-check executed by bash
#   dash         Debian, fio-check executed by dash
#
# The repository is mounted read-only at /src; nothing is written back.
# Exit: 0 = every target passed, 1 = one or more failed, 2 = usage error
# =============================================================================
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX="${ROOT}/tests/docker"
IMAGE="fio-check-test"
TEST_ARGS=""

[ "${1:-}" = "-v" ] && { TEST_ARGS="-v"; shift; }
targets="${*:-busybox-oe busybox-lmp bash dash}"

command -v docker >/dev/null 2>&1 || { echo "docker not found" >&2; exit 2; }

# build <target> — build the image for a target, print its tag
build() {
    case "$1" in
        busybox-oe|busybox-lmp)
            docker build -q -f "${CTX}/Dockerfile.busybox" \
                --build-arg BUSYBOX_VARIANT="${1#busybox-}" \
                -t "${IMAGE}:$1" "${CTX}" >/dev/null ;;
        bash|dash)
            docker build -q -f "${CTX}/Dockerfile.bash" \
                -t "${IMAGE}:debian" "${CTX}" >/dev/null ;;
    esac
}

# run_target <target> — run the suite; harness and fio-check share the shell
run_target() {
    local tag harness fio_shell
    case "$1" in
        busybox-oe|busybox-lmp) tag="$1";    harness="sh";   fio_shell="sh" ;;
        bash)                   tag="debian"; harness="bash"; fio_shell="bash" ;;
        dash)                   tag="debian"; harness="dash"; fio_shell="dash" ;;
    esac
    # shellcheck disable=SC2086
    docker run --rm -v "${ROOT}:/src:ro" -e FIO_SHELL="${fio_shell}" \
        "${IMAGE}:${tag}" "${harness}" ./test_fio_check.sh ${TEST_ARGS}
}

results=""
any_fail=0
for t in ${targets}; do
    case "${t}" in
        busybox-oe|busybox-lmp|bash|dash) ;;
        *) echo "unknown target: ${t}" >&2; exit 2 ;;
    esac
    printf '\n==== %s ====\n' "${t}"
    if ! build "${t}"; then
        results="${results}${t}: BUILD FAILED
"
        any_fail=1
        continue
    fi
    if run_target "${t}"; then
        results="${results}${t}: PASS
"
    else
        results="${results}${t}: FAIL
"
        any_fail=1
    fi
done

printf '\n==== Summary ====\n%s' "${results}"
exit "${any_fail}"
