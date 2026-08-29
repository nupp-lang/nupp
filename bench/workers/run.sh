#!/bin/sh
set -eu

cd "$(dirname "$0")"
../../bin/nupp build --target worker-benchmark --progress=never
exec ./worker-benchmark "$@"
