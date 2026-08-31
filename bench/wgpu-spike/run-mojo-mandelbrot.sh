#!/bin/sh
# Run the matched Mojo GPU control with Nupp's exact binary32 semantics.
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$ROOT"

MOJO=${MOJO:-mojo}
exec "$MOJO" --fp-mode contract=off \
    bench/wgpu-spike/mandelbrot-mojo.mojo
