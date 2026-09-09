#!/bin/sh
# Cold, unchanged and one-unit-edit timings for the shapes an ahead-of-time
# project comes in.
#
#   ./run.sh [RUNS]           every shape, RUNS repetitions, minimum reported
#   SHAPES="wide" ./run.sh    one of them
#   NUPP=/path/to/bin/nupp ./run.sh   another compiler, for a before/after pair
#
# Projects are generated into a scratch directory rather than committed: what is
# being measured is how a build behaves when a project has one `@aot` body,
# several, or several feature tiers of each, and those differ only in how many
# files the generator writes.
#
# The minimum of RUNS rather than the mean. These are wall-clock timings of a
# process that starts a C compiler, and a development machine running anything
# else lengthens some runs and none of them shorten: the fastest observed run is
# the one least contaminated by whatever else the machine was doing. Record the
# load average beside any number taken from here.
set -eu

cd "$(dirname "$0")"
NUPP=${NUPP:-$(cd ../.. && pwd)/bin/nupp}
RUNS=${1:-3}
SHAPES=${SHAPES:-"small multisource multiversion wide wasm"}
WORK=${WORK:-${TMPDIR:-/tmp}/nupp-aot-incremental-bench}

now() { perl -MTime::HiRes=time -e 'printf "%.1f\n", time*1000'; }

# x86-64 is the architecture with several feature tiers, so a multiversioned
# shape has to be built for one. A machine that is one needs nothing said; an
# Apple ARM64 machine cross-compiles to its own operating system's x86-64
# triple, which its C compiler can do with the SDK it already has. Anywhere else
# this needs a sysroot the machine may not have, and says so rather than
# pretending the shape was measured.
tiered_target() {
    case "$(uname -m 2>/dev/null)" in
        x86_64|amd64) printf '' ;;
        *)
            case "$(uname -s 2>/dev/null)" in
                Darwin) printf 'aotTarget = "x86_64-apple-darwin", ' ;;
                *) printf 'aotTarget = "x86_64-unknown-linux-gnu", ' ;;
            esac
            ;;
    esac
}

# One `@aot` body per module, each with a literal only it uses, so editing one
# module's body changes that module's IR and nothing else's.
kernel() {
    cat <<EOF
module k$1

local span = require("nupp.mem.span")

@aot(vectorize = true)
local function scale$1(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>, factor: number): nil
    if #out ~= #input then
        error("length mismatch", 2)
    end
    for i = 1, #out do
        out[i] = input[i] * factor + $1.0
    end
end

@aot(vectorize = false)
local function total$1(borrows input: span.Span<uint8>): number
    local sum = 0.0
    for i = 1, #input do
        sum = sum + input[i]
    end
    return sum
end

export = {scale = scale$1, total = total$1}
EOF
}

# SHAPE DIR: the project each shape is.
generate() {
    shape=$1
    dir=$2
    rm -rf "$dir"
    mkdir -p "$dir/src"
    case "$shape" in
        small) count=1; policy=require; extra="" ;;
        multisource) count=8; policy=require; extra="" ;;
        multiversion) count=4; policy=require; extra="$(tiered_target)aotFeatures = \"avx2\"," ;;
        wide) count=16; policy=require; extra="$(tiered_target)aotFeatures = \"avx2\"," ;;
        wasm) count=4; policy=require-wasm; extra='dialect = "lua51",' ;;
        *) echo "unknown shape $shape" >&2; exit 2 ;;
    esac
    entries=""
    index=0
    while [ "$index" -lt "$count" ]; do
        kernel "$index" > "$dir/src/k$index.nupp"
        if [ -z "$entries" ]; then entries="\"k$index\""; else entries="$entries, \"k$index\""; fi
        index=$((index + 1))
    done
    cat > "$dir/nupp.lua" <<EOF
return {
   include = {"src"},
   build = {targets = {native = {
      kind = "modules", entries = {$entries}, outDir = "build/native",
      aot = "$policy", $extra
   }}},
}
EOF
}

# Reports the wall time and what the policy did, from the build's own report.
timed() {
    dir=$1
    started=$(now)
    (cd "$dir" && "$NUPP" build --target native --format json > report.json 2>build.err) || true
    finished=$(now)
    grep -q '"ok":true' "$dir/report.json" || {
        echo "build failed in $dir" >&2
        cat "$dir/build.err" >&2
        head -c 1500 "$dir/report.json" >&2
        exit 1
    }
    perl -e "printf '%.0f', $finished - $started"
}

facts() {
    perl -ne 'print "$1\n" if /"aot":\{(.*?)\}/' "$1/report.json" | head -n 1
}

printf '%-14s %9s %9s %9s\n' shape cold unchanged edit
for shape in $SHAPES; do
    dir="$WORK/$shape"
    best_cold=; best_unchanged=; best_edit=
    run=0
    while [ "$run" -lt "$RUNS" ]; do
        run=$((run + 1))
        generate "$shape" "$dir"
        cold=$(timed "$dir")
        unchanged=$(timed "$dir")
        unchangedFacts=$(facts "$dir")
        perl -pi -e 's/factor \+ [\d.]+/"factor + " . (int(rand(900)) + 1) . ".0"/e' "$dir/src/k0.nupp"
        edit=$(timed "$dir")
        editFacts=$(facts "$dir")
        [ -z "$best_cold" ] || [ "$cold" -lt "$best_cold" ] && best_cold=$cold
        [ -z "$best_unchanged" ] || [ "$unchanged" -lt "$best_unchanged" ] && best_unchanged=$unchanged
        [ -z "$best_edit" ] || [ "$edit" -lt "$best_edit" ] && best_edit=$edit
    done
    printf '%-14s %8sms %8sms %8sms\n' "$shape" "$best_cold" "$best_unchanged" "$best_edit"
    printf '  unchanged  %s\n' "$unchangedFacts"
    printf '  one edit   %s\n' "$editFacts"
done
