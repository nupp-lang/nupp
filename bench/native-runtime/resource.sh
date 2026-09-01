#!/bin/sh
set -eu

cd "$(dirname "$0")"

../../bin/nupp build --progress=never

NUPP_BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/nupp-native-resource.XXXXXX")
PORT_FILE="$NUPP_BENCH_TEMP/port"
node server.mjs "$PORT_FILE" &
SERVER_PID=$!
BENCH_PID=
cleanup() {
   if [ -n "$BENCH_PID" ]; then
      kill "$BENCH_PID" 2>/dev/null || true
      wait "$BENCH_PID" 2>/dev/null || true
   fi
   kill "$SERVER_PID" 2>/dev/null || true
   wait "$SERVER_PID" 2>/dev/null || true
   rm -rf "$NUPP_BENCH_TEMP"
}
trap cleanup EXIT HUP INT TERM

attempt=0
while [ ! -s "$PORT_FILE" ]; do
   attempt=$((attempt + 1))
   if [ "$attempt" -ge 500 ]; then
      echo "native runtime benchmark: HTTP peer did not start" >&2
      exit 1
   fi
   sleep 0.01
done

NUPP_BENCH_HTTP_PORT=$(cat "$PORT_FILE")
export NUPP_BENCH_HTTP_PORT

measure() {
   mode=$1
   output="$NUPP_BENCH_TEMP/$mode.out"
   ./build/native-runtime-benchmark "$mode" >"$output" &
   BENCH_PID=$!
   attempt=0
   while ! grep -q '^READY ' "$output" 2>/dev/null; do
      attempt=$((attempt + 1))
      if [ "$attempt" -ge 500 ]; then
         echo "$mode did not become ready" >&2
         exit 1
      fi
      sleep 0.01
   done
   for second in 1 3 5; do
      sleep "$([ "$second" -eq 1 ] && echo 1 || echo 2)"
      rss=$(ps -o rss= -p "$BENCH_PID" | tr -d ' ')
      printf '%s second=%s rss_kib=%s\n' "$mode" "$second" "$rss"
   done
   kill "$BENCH_PID" 2>/dev/null || true
   wait "$BENCH_PID" 2>/dev/null || true
   BENCH_PID=
}

measure_load() {
   output="$NUPP_BENCH_TEMP/load.out"
   ./build/native-runtime-benchmark >"$output" &
   BENCH_PID=$!
   peak=0
   while kill -0 "$BENCH_PID" 2>/dev/null; do
      rss=$(ps -o rss= -p "$BENCH_PID" 2>/dev/null | tr -d ' ' || true)
      if [ -n "$rss" ] && [ "$rss" -gt "$peak" ]; then
         peak=$rss
      fi
      sleep 0.05
   done
   wait "$BENCH_PID"
   BENCH_PID=
   printf 'load peak_rss_kib=%s\n' "$peak"
}

measure_load
measure net-slow-reader
measure http-slow-reader
