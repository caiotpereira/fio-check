#!/bin/sh
# =============================================================================
# tests/validate-profiles.sh — validate every layer profile against every
# expectation set and machine
#
# The matrix is discovered, not listed: each profiles/<layer>/ that has an
# expect/ directory contributes
#     every profile  x  every expect/<set>.sh  x  every machine/<m>.sh (or none)
# so adding profiles/meta-lmp/expect/v98.sh or a new meta-foundries profile
# extends the matrix with no change here.
#
# Each combination runs as its own fio-check process against a fresh fixture
# rootfs built for the profile (its "# Fixture :" header), in --root mode, and
# writes its own report. One failing combination never stops the others, and
# every combination prints the command that reproduces it alone.
#
# Usage:
#   tests/validate-profiles.sh [options]
#     --layer <name>     only this layer (meta-lmp, meta-foundries); repeatable
#     --expect <name>    only this expectation set; repeatable
#     --report-dir <d>   keep per-run reports in <d> (default: temporary)
#     --shell <sh>       shell that executes fio-check.sh (default: sh)
#     -v                 print the failures of each failing run
#
# Exit: 0 = every combination passed, 1 = one or more failed, 2 = usage error
# =============================================================================
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIO="${ROOT}/fio-check.sh"
MKFS="${ROOT}/tests/fixtures/make-rootfs.sh"
PROFILES="${ROOT}/profiles"

layers=""
expects=""
report_dir=""
fio_shell="sh"
verbose=0

while [ $# -gt 0 ]; do
    case "$1" in
        --layer)      [ -n "${2:-}" ] || exit 2; layers="${layers} $2"; shift ;;
        --expect)     [ -n "${2:-}" ] || exit 2; expects="${expects} $2"; shift ;;
        --report-dir) [ -n "${2:-}" ] || exit 2; report_dir="$2"; shift ;;
        --shell)      [ -n "${2:-}" ] || exit 2; fio_shell="$2"; shift ;;
        -v)           verbose=1 ;;
        -h|--help)    sed -n '2,/^# ====/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *)            echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT INT TERM
[ -n "${report_dir}" ] && mkdir -p "${report_dir}"
reports="${report_dir:-${work}/reports}"
mkdir -p "${reports}"

# names <dir> — basenames of the .sh files in <dir>
names() {
    [ -d "$1" ] || return 0
    find "$1" -mindepth 1 -maxdepth 1 -type f -name '*.sh' | sort | sed 's|.*/||; s|\.sh$||'
}

# selected <word> <list> — 0 when <list> is empty or contains <word>
selected() {
    [ -z "$2" ] && return 0
    case " $2 " in *" $1 "*) return 0 ;; esac
    return 1
}

total=0
failed=0
results="${work}/results"
: > "${results}"

# run_one <layer> <profile> <expect> <machine|-> <fixture>
run_one() {
    local layer="$1" profile="$2" expect="$3" machine="$4" fixture="$5"
    local id="${layer}/${profile} expect=${expect}"
    local mopt="" hwid="qemux86-64"
    if [ "${machine}" != "-" ]; then
        id="${id} machine=${machine}"
        mopt="--machine ${machine}"
        hwid="${machine}"
    fi
    local tag; tag="$(printf '%s_%s_%s_%s' "${layer}" "${profile}" "${expect}" "${machine}" | tr '/ ' '__')"
    local fx="${work}/fx_${tag}"
    local report="${reports}/${tag}.txt"

    total=$(( total + 1 ))
    if ! sh "${MKFS}" "${fx}" "${fixture}" "${hwid}" >/dev/null 2>&1; then
        printf '%s\tFAIL\tfixture %s could not be built\n' "${id}" "${fixture}" >> "${results}"
        failed=$(( failed + 1 ))
        return
    fi

    local out="${work}/out_${tag}"
    # shellcheck disable=SC2086
    ${fio_shell} "${FIO}" --no-color -r "${report}" --root "${fx}" --kconfig "${fx}.kconfig" \
        --expect "${expect}" ${mopt} run-profile "${layer}/${profile}" > "${out}" 2>&1
    local rc=$?
    local counts; counts="$(grep -E 'PASS: [0-9]+' "${out}" | tail -n 1 | sed 's/^ *//')"
    if [ "${rc}" -eq 0 ]; then
        printf '%s\tPASS\t%s\n' "${id}" "${counts}" >> "${results}"
    else
        failed=$(( failed + 1 ))
        printf '%s\tFAIL\t%s\n' "${id}" "${counts:-exit ${rc}}" >> "${results}"
        printf '  reproduce: tests/fixtures/make-rootfs.sh /tmp/fx %s %s && \\\n' "${fixture}" "${hwid}" >> "${results}.repro"
        printf '             ./fio-check.sh --root /tmp/fx --kconfig /tmp/fx.kconfig --expect %s %s run-profile %s/%s\n' \
            "${expect}" "${mopt}" "${layer}" "${profile}" >> "${results}.repro"
        if [ "${verbose}" -eq 1 ]; then
            printf '\n--- %s\n' "${id}"
            grep -E '^ \[(FAIL|WARN)\]' "${out}" | head -n 20
        fi
    fi
    rm -rf "${fx}" "${fx}.kconfig"
}

for ldir in "${PROFILES}"/*/; do
    layer="$(basename "${ldir}")"
    [ -d "${ldir}expect" ] || continue
    selected "${layer}" "${layers}" || continue
    machines="$(names "${ldir}machine")"
    [ -n "${machines}" ] || machines="-"
    for profile in $(names "${ldir%/}"); do
        case "${profile}" in _*) continue ;; esac
        fixture="$(sed -n 's/^# Fixture *: *\([a-z-]*\).*/\1/p' "${ldir}${profile}.sh" | head -n 1)"
        if [ -z "${fixture}" ]; then
            printf '%s/%s\tSKIP\tno "# Fixture :" header\n' "${layer}" "${profile}" >> "${results}"
            continue
        fi
        for expect in $(names "${ldir}expect"); do
            selected "${expect}" "${expects}" || continue
            for machine in ${machines}; do
                run_one "${layer}" "${profile}" "${expect}" "${machine}" "${fixture}"
            done
        done
    done
done

printf '\n%-68s %s\n' "Combination" "Result"
printf '%s\n' "------------------------------------------------------------------------------------------"
tab="$(printf '\t')"
while IFS="${tab}" read -r id status detail; do
    printf '%-68s %-4s  %s\n' "${id}" "${status}" "${detail}"
done < "${results}"
printf '%s\n' "------------------------------------------------------------------------------------------"
printf '%d combination(s), %d failed. Reports: %s\n' "${total}" "${failed}" "${report_dir:-<temporary>}"
if [ -f "${results}.repro" ]; then
    printf '\nRe-run a failing combination alone:\n'
    cat "${results}.repro"
fi

[ "${total}" -gt 0 ] || { echo "no combinations found" >&2; exit 1; }
[ "${failed}" -eq 0 ]
