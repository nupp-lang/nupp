#!/bin/sh
set -eu

json=false
if [ "${1:-}" = "--json" ]; then
    json=true
    shift
fi
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    echo "usage: $0 [--json] BASELINE_ROOT CANDIDATE_ROOT [SAMPLES]" >&2
    exit 2
fi

baseline=$1
candidate=$2
samples=${3:-15}
case "$samples" in
    *[!0-9]*|'') echo "samples must be an integer" >&2; exit 2 ;;
esac
if [ "$samples" -lt 15 ]; then
    echo "samples must be at least 15" >&2
    exit 2
fi

here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
corpus=$here/corpus
scratch=$(mktemp -d "${TMPDIR:-/tmp}/nupp-aot-fold-dispatch.XXXXXX")
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
baseline_cache=$scratch/baseline-cache
candidate_cache=$scratch/candidate-cache

# A fixpoint run finishes with a bytecode index rooted at its temporary stage.
# Rebuild each ordinary compiler before comparing so a candidate is not timed
# parsing generated Lua while its baseline loads bytecode from the real tree.
(cd "$baseline" && ./bin/nupp build >/dev/null)
(cd "$candidate" && ./bin/nupp build >/dev/null)

for artifact in ir c; do
    (cd "$corpus" && "$baseline/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit "$artifact" folds.nupp) > "$scratch/baseline.$artifact"
    (cd "$corpus" && "$candidate/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit "$artifact" folds.nupp) > "$scratch/candidate.$artifact"
    if ! cmp -s "$scratch/baseline.$artifact" "$scratch/candidate.$artifact"; then
        diff -u "$scratch/baseline.$artifact" "$scratch/candidate.$artifact" >&2 || true
        echo "$artifact output differs; timing refused" >&2
        exit 1
    fi
done

# Warm both content-addressed compiler caches before taking paired samples.
(cd "$corpus" && NUPP_CACHE_DIR="$baseline_cache" "$baseline/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit ir folds.nupp) >/dev/null
(cd "$corpus" && NUPP_CACHE_DIR="$candidate_cache" "$candidate/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit ir folds.nupp) >/dev/null

: > "$scratch/baseline.samples"
: > "$scratch/candidate.samples"
sample=1
while [ "$sample" -le "$samples" ]; do
    if [ $((sample % 2)) -eq 1 ]; then
        baseline_time=$({ /usr/bin/time -p sh -c 'cd "$1" && NUPP_CACHE_DIR="$3" "$2/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit ir folds.nupp >/dev/null' sh "$corpus" "$baseline" "$baseline_cache"; } 2>&1 | awk '/^real / {print $2}')
        candidate_time=$({ /usr/bin/time -p sh -c 'cd "$1" && NUPP_CACHE_DIR="$3" "$2/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit ir folds.nupp >/dev/null' sh "$corpus" "$candidate" "$candidate_cache"; } 2>&1 | awk '/^real / {print $2}')
    else
        candidate_time=$({ /usr/bin/time -p sh -c 'cd "$1" && NUPP_CACHE_DIR="$3" "$2/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit ir folds.nupp >/dev/null' sh "$corpus" "$candidate" "$candidate_cache"; } 2>&1 | awk '/^real / {print $2}')
        baseline_time=$({ /usr/bin/time -p sh -c 'cd "$1" && NUPP_CACHE_DIR="$3" "$2/bin/nupp" aot --target x86_64-unknown-linux-gnu --emit ir folds.nupp >/dev/null' sh "$corpus" "$baseline" "$baseline_cache"; } 2>&1 | awk '/^real / {print $2}')
    fi
    echo "$baseline_time" >> "$scratch/baseline.samples"
    echo "$candidate_time" >> "$scratch/candidate.samples"
    sample=$((sample + 1))
done

median() {
    sort -n "$1" | awk '{v[NR]=$1} END {if (NR % 2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}'
}
baseline_median=$(median "$scratch/baseline.samples")
candidate_median=$(median "$scratch/candidate.samples")
paired=$(paste "$scratch/baseline.samples" "$scratch/candidate.samples" | awk '{print $2/$1}')
paired_median=$(printf '%s\n' "$paired" | sort -n | awk '{v[NR]=$1} END {if (NR % 2) print v[(NR+1)/2]; else print (v[NR/2]+v[NR/2+1])/2}')

if [ "$json" = true ]; then
    baseline_json=$(awk 'BEGIN{printf "["} {if (NR>1) printf ","; printf "%s", $1} END{print "]"}' "$scratch/baseline.samples")
    candidate_json=$(awk 'BEGIN{printf "["} {if (NR>1) printf ","; printf "%s", $1} END{print "]"}' "$scratch/candidate.samples")
    paired_json=$(printf '%s\n' "$paired" | awk 'BEGIN{printf "["} {if (NR>1) printf ","; printf "%s", $1} END{print "]"}')
    printf '{"samples":%s,"baseline":{"raw":%s,"median":%s},"candidate":{"raw":%s,"median":%s},"pairedRatios":%s,"pairedMedian":%s}\n' \
        "$samples" "$baseline_json" "$baseline_median" "$candidate_json" "$candidate_median" "$paired_json" "$paired_median"
else
    echo "baseline samples: $(tr '\n' ' ' < "$scratch/baseline.samples")"
    echo "candidate samples: $(tr '\n' ' ' < "$scratch/candidate.samples")"
    echo "baseline median: $baseline_median s"
    echo "candidate median: $candidate_median s"
    echo "paired candidate/baseline median: $paired_median"
fi
