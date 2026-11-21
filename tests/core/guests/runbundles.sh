#!/bin/sh
# Runs guest bundles another host emitted (run.lua with NUPP_GUEST_EMIT_ONLY=1)
# on this one, through its C bridge and ABI guard, and holds each to the
# result word its case expects. An ARM64 bundle is one program on every ARM64
# host, so Windows ARM64 runs the bundles Linux ARM64 lowers.
#
#   tests/core/guests/runbundles.sh DIRECTORY BRIDGE GUARD [CASE...]
#
# DIRECTORY holds NAME-normal.bundle and NAME-normal.expected for each case,
# and lib/ beside them for what the bundles load relative to themselves. With
# no CASE every bundle there runs. The environment is the guest run's.
set -u
[ "$#" -ge 3 ] || { echo "usage: runbundles.sh DIRECTORY BRIDGE GUARD [CASE...]" >&2; exit 2; }
directory=$1 bridge=$2 guard=$3
shift 3
cd "$directory" || exit 2
long=$(printf '%300s' '' | tr ' ' x)
temp=$PWD/temp
mkdir -p "$temp"
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) temp=$(cygpath -m "$temp") ;; esac
: > empty.bin
if [ "$#" -eq 0 ]; then
    for bundle in *-normal.bundle; do set -- "$@" "${bundle%-normal.bundle}"; done
fi
passed=0 failed=0
for name in "$@"; do
    status=ok
    NUPP_GUEST_PROBE=core-environment NUPP_GUEST_SCALE=3 NUPP_GUEST_LONG=$long NUPP_GUEST_TEMP=$temp \
        "$bridge" "$name-normal.bundle" empty.bin "$name.out" > "$name.stdout" 2> "$name.stderr" || status="bridge exited $?"
    if [ "$status" = ok ] && ! cmp -s "$name.out" "$name-normal.expected"; then
        status="result differs"
    fi
    if [ "$status" = ok ]; then
        NUPP_GUEST_PROBE=core-environment NUPP_GUEST_SCALE=3 NUPP_GUEST_LONG=$long NUPP_GUEST_TEMP=$temp \
            CORE_TEST_BUNDLE="$name-normal.bundle" CORE_TEST_INPUT=empty.bin \
            CORE_TEST_EXPECTED="$name-normal.expected" \
            "$guard" --ignored --exact abi::generated_entry_preserves_c_abi_and_output --test-threads=1 \
            > "$name.guard" 2>&1 || status="guard failed"
    fi
    if [ "$status" = ok ]; then
        passed=$((passed + 1))
        echo "PASS $name"
    else
        failed=$((failed + 1))
        echo "FAIL $name: $status"
        head -c 2000 "$name.stderr" | sed 's/^/    /'
    fi
done
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
