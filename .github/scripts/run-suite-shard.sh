#!/usr/bin/env bash

# Run one shard of a suite selection.
#
#   run-suite-shard.sh SHARD SHARDS BATCH JOBS SELECTION...
#
# SELECTION is what names the suites (`--lane=shared --exclude-group=...`, or
# `--group=native-runtime`). Every shard of one selection lists it and deals the
# suites out the same way, so the shards partition the selection without any of
# them being told what the others took.
#
# The deal is by recorded duration (`TIMINGS`, the runner's suite timings):
# heaviest first, each to the shard with the least so far. Dealing sorted names
# in turn left one Linux shard at fifty minutes beside two at thirty, because
# the slowest suites share prefixes. Every shard of a platform reads the same
# file -- the one the test runner's cache carries -- so they all deal alike; a
# suite with no record counts as the median of those that have one.
#
# A shard runs its suites BATCH at a time, each batch in workers of its own. A
# shared-lane worker keeps every module its suites load (#115), so what bounds
# a runner's memory is how many suites one set of workers lives through, not
# how many the shard has. BATCH 0 runs the shard as one batch, and JOBS 0
# leaves the worker count to the runner.

set -euo pipefail

shard=$1
shards=$2
batch=$3
jobs=$4
shift 4

runner=(./bin/nupp test)

timings=${TIMINGS:-build/test-runner/.nupp-test-times.json}
recorded=""
if [ -f "$timings" ] && command -v jq > /dev/null 2>&1; then
    recorded=$(jq -r '.suites // {} | to_entries[] | "\(.key) \(.value)"' "$timings" 2>/dev/null || true)
fi

listed=$("${runner[@]}" --scope=all "$@" --list-suites | tr -d '\r' \
    | grep -E '^[A-Za-z0-9_./-]+$' | LC_ALL=C sort)
total=$(printf '%s\n' "$listed" | grep -c . || true)
if [ "$total" -eq 0 ]; then
    echo "the selection $* lists no suites" >&2
    exit 1
fi

mine=$({
    printf '%s\n' "$recorded" | sed 's/^/time /'
    printf '%s\n' "$listed" | sed 's/^/suite /'
} | awk -v n="$shards" -v k="$shard" '
    $1 == "time" && NF == 3 { known[$2] = $3; next }
    $1 == "suite" && NF == 2 { names[++count] = $2 }
    END {
        # The median of the suites listed here that have a record.
        m = 0
        for (i = 1; i <= count; i++) if (names[i] in known) values[++m] = known[names[i]]
        for (i = 2; i <= m; i++) { v = values[i]; for (j = i - 1; j >= 1 && values[j] > v; j--) values[j + 1] = values[j]; values[j + 1] = v }
        median = m > 0 ? values[int((m + 1) / 2)] : 1
        for (i = 1; i <= count; i++) {
            weight[i] = names[i] in known ? known[names[i]] : median
            order[i] = i
        }
        # Heaviest first; names break ties, so every shard sorts alike.
        for (i = 2; i <= count; i++) {
            v = order[i]
            for (j = i - 1; j >= 1 && (weight[order[j]] < weight[v] || weight[order[j]] == weight[v] && names[order[j]] > names[v]); j--) order[j + 1] = order[j]
            order[j + 1] = v
        }
        for (s = 1; s <= n; s++) load[s] = 0
        sum = 0
        for (i = 1; i <= count; i++) {
            best = 1
            for (s = 2; s <= n; s++) if (load[s] < load[best]) best = s
            load[best] += weight[order[i]]
            sum += weight[order[i]]
            if (best == k) print names[order[i]]
        }
        printf "shard %d of %d: about %.0f of %.0f suite-seconds\n", k, n, load[k] / 1000, sum / 1000 > "/dev/stderr"
    }' | LC_ALL=C sort)
count=$(printf '%s\n' "$mine" | grep -c . || true)
echo "shard $shard of $shards: $count of $total suites"
if [ "$count" -eq 0 ]; then
    exit 0
fi

if printf '%s\n' "$mine" | grep -Eq '^tools/docs(/|$)'; then
    library=$(sh scripts/markdown-library)
    export NUPP_MARKDOWN_LIBRARY="$library"
fi

if [ "$batch" -le 0 ]; then
    batch=$count
fi
workers=()
if [ "$jobs" -gt 0 ]; then
    workers=(--jobs="$jobs")
fi

# The runner adds a named group to the suites named beside it rather than
# narrowing one by the other, so a shard that passed its group along ran the
# whole group. The names are the group's already; only filters go with them.
filters=()
for argument in "$@"; do
    case "$argument" in
        --group=*) ;;
        *) filters+=("$argument") ;;
    esac
done

status=0
start=1
while [ "$start" -le "$count" ]; do
    # shellcheck disable=SC2207 # suite names hold no spaces or globs.
    names=($(printf '%s\n' "$mine" | sed -n "${start},$((start + batch - 1))p"))
    echo "::group::${names[0]} .. ${names[${#names[@]} - 1]}"
    # The `+` form is for bash 3.2, where expanding an empty array is an
    # unbound variable under `set -u`.
    "${runner[@]}" --fresh --scope=all ${filters[@]+"${filters[@]}"} ${workers[@]+"${workers[@]}"} \
        "${names[@]}" || status=1
    echo "::endgroup::"
    start=$((start + batch))
done
exit "$status"
