#!/bin/sh
set -eu

cd "$(dirname "$0")"

../../bin/nupp build --progress=never

NUPP_BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/nupp-native-bench.XXXXXX")
. ./peer.sh
cleanup() {
   stop_native_benchmark_peer
   rm -rf "$NUPP_BENCH_TEMP"
}
trap cleanup EXIT HUP INT TERM
if ! start_native_benchmark_peer "$NUPP_BENCH_TEMP"; then
   exit 1
fi

export NUPP_BENCH_HTTP_PORT NUPP_BENCH_NET_PORT
./build/native-runtime-benchmark "$@"
