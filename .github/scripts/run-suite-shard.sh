#!/usr/bin/env bash

# Run one shard of a suite selection.
#
#   run-suite-shard.sh SHARD SHARDS BATCH JOBS SELECTION...
#
# SELECTION is what names the suites (`--lane=shared --exclude-group=...`, or
# `--group=native-runtime`). Every shard of one selection lists it, sorts the
# names and keeps each SHARDS-th one starting at its own index, so the shards
# partition the selection without any of them being told what the others took:
# the list is a function of the tree, and they all have the same tree. Suites
# that sort together tend to cost alike -- the native graph suites are the
# slowest in the tree and all begin `native` -- so dealing them out in turn
# also spreads the cost, where cutting the list into runs would not.
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

listed=$("${runner[@]}" --scope=all "$@" --list-suites | tr -d '\r' \
    | grep -E '^[A-Za-z0-9_./-]+$' | LC_ALL=C sort)
total=$(printf '%s\n' "$listed" | grep -c . || true)
if [ "$total" -eq 0 ]; then
    echo "the selection $* lists no suites" >&2
    exit 1
fi

mine=$(printf '%s\n' "$listed" | awk -v n="$shards" -v k="$shard" '(NR - 1) % n == k - 1')
count=$(printf '%s\n' "$mine" | grep -c . || true)
echo "shard $shard of $shards: $count of $total suites"
if [ "$count" -eq 0 ]; then
    exit 0
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
