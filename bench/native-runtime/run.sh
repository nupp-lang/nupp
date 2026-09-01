#!/bin/sh
set -eu

cd "$(dirname "$0")"

../../bin/nupp build --progress=never

NUPP_BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/nupp-native-bench.XXXXXX")
HTTP_PORT_FILE="$NUPP_BENCH_TEMP/http-port"
NET_PORT_FILE="$NUPP_BENCH_TEMP/net-port"
node server.mjs "$HTTP_PORT_FILE" "$NET_PORT_FILE" &
SERVER_PID=$!
cleanup() {
   kill "$SERVER_PID" 2>/dev/null || true
   wait "$SERVER_PID" 2>/dev/null || true
   rm -rf "$NUPP_BENCH_TEMP"
}
trap cleanup EXIT HUP INT TERM

attempt=0
while [ ! -s "$HTTP_PORT_FILE" ] || [ ! -s "$NET_PORT_FILE" ]; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 500 ]; then
      echo "native runtime benchmark: HTTP peer did not start" >&2
      exit 1
   fi
   sleep 0.01
done

NUPP_BENCH_HTTP_PORT=$(cat "$HTTP_PORT_FILE")
NUPP_BENCH_NET_PORT=$(cat "$NET_PORT_FILE")
export NUPP_BENCH_HTTP_PORT NUPP_BENCH_NET_PORT
./build/native-runtime-benchmark "$@"
