#!/bin/sh
# Compare Nupp and Forgo over one byte-identical binary32 Mandelbrot contract.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

FORGO_ROOT=${FORGO_ROOT:-"$(dirname "$ROOT")/forgo"}
FORGO_GOROOT=${FORGO_GOROOT:-"$FORGO_ROOT"}
FORGO_BIN=${FORGO_BIN:-"$FORGO_GOROOT/bin/forgo"}
if [ ! -x "$FORGO_BIN" ]; then
    echo "forgo comparison: set FORGO_BIN and FORGO_GOROOT to a built Forgo toolchain" >&2
    exit 2
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

MANDELBROT_RESULTS="$WORK/nupp.bin" \
bench/simd-mandelbrot/run.sh >"$WORK/nupp.txt"

(
    cd "$FORGO_ROOT/examples/mandelbrot"
    GOROOT="$FORGO_GOROOT" GOCACHE="$WORK/gocache" GOPATH="$WORK/gopath" \
        MANDELBROT_RESULTS="$WORK/forgo.bin" \
        "$FORGO_BIN" run . 1024 768 256
) >"$WORK/forgo.txt"

if ! cmp -s "$WORK/nupp.bin" "$WORK/forgo.bin"; then
    echo "forgo comparison: per-pixel results differ" >&2
    cmp "$WORK/nupp.bin" "$WORK/forgo.bin" || true
    exit 1
fi

echo "Nupp"
cat "$WORK/nupp.txt"
echo "Forgo"
cat "$WORK/forgo.txt"
echo "786432 per-pixel results agree byte-for-byte"
