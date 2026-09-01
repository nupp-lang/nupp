#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)

# Native feature runtimes are compiler-owned artifacts.  The complete
# measurement wrapper builds them before entering this project, but this
# command is also a documented direct entry point and must establish the same
# prerequisite on a clean checkout.
(cd "$ROOT" && ./bin/nupp build --target compiler --progress=never)

cd "$ROOT/bench/native-runtime"

../../bin/nupp build --progress=never

NUPP_BENCH_TEMP=$(mktemp -d "${TMPDIR:-/tmp}/nupp-native-resource.XXXXXX")
. ./peer.sh
BENCH_PID=
cleanup() {
   if [ -n "$BENCH_PID" ]; then
      kill "$BENCH_PID" 2>/dev/null || true
      wait "$BENCH_PID" 2>/dev/null || true
   fi
   stop_native_benchmark_peer
   rm -rf "$NUPP_BENCH_TEMP"
}
trap cleanup EXIT HUP INT TERM
if ! start_native_benchmark_peer "$NUPP_BENCH_TEMP"; then
   exit 1
fi

export NUPP_BENCH_HTTP_PORT NUPP_BENCH_NET_PORT

case "${RUNNER_OS:-}:$(uname -s 2>/dev/null || printf unknown)" in
   Windows:*|*:MINGW*|*:MSYS*|*:CYGWIN*) WINDOWS=1 ;;
   *) WINDOWS=0 ;;
esac

if [ "$WINDOWS" -eq 1 ]; then
   benchmark="$PWD/build/native-runtime-benchmark"
   if [ -f "$benchmark.exe" ]; then
      benchmark="$benchmark.exe"
   fi
   powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass \
      -File "$(cygpath -w "$PWD/resource-windows.ps1")" \
      -Benchmark "$(cygpath -w "$benchmark")" \
      -OutputDirectory "$(cygpath -w "$NUPP_BENCH_TEMP")"
   exit
fi

rss_kib() {
   pid=$1
   if ! rss=$(ps -o rss= -p "$pid"); then
      echo "unable to sample PID $pid" >&2
      return 1
   fi
   rss=$(printf '%s' "$rss" | tr -d '\r ')
   case "$rss" in
      ''|*[!0-9]*|0)
         echo "invalid RSS sample for PID $pid: $rss" >&2
         return 1
         ;;
      *) printf '%s\n' "$rss" ;;
   esac
}

benchmark_pid() {
   output=$1
   lifecycle_pid=$2
   mode=$3
   attempt=0
   while true; do
      if native_pid=$(awk '
         { sub(/\r$/, "") }
         $1 == "NUPP_BENCH_PID" {
            markers++
            if (NF == 2 && $2 ~ /^[0-9]+$/ && $2 > 0) answer = $2
         }
         END {
            if (markers == 1 && answer != "") print answer
            else exit 1
         }
      ' "$output" 2>/dev/null); then
         printf '%s\n' "$native_pid"
         return 0
      fi
      if ! kill -0 "$lifecycle_pid" 2>/dev/null; then
         sed 's/^/'"$mode"': /' "$output" >&2
         echo "$mode ended before reporting its native process ID" >&2
         return 1
      fi
      attempt=$((attempt + 1))
      if [ "$attempt" -ge 500 ]; then
         sed 's/^/'"$mode"': /' "$output" >&2
         echo "$mode did not report its native process ID" >&2
         return 1
      fi
      sleep 0.01
   done
}

measure() {
   mode=$1
   output="$NUPP_BENCH_TEMP/$mode.out"
   ./build/native-runtime-benchmark "$mode" >"$output" &
   BENCH_PID=$!
   native_pid=$(benchmark_pid "$output" "$BENCH_PID" "$mode")
   attempt=0
   while ! grep -q '^READY ' "$output" 2>/dev/null; do
      if ! kill -0 "$BENCH_PID" 2>/dev/null; then
         wait "$BENCH_PID" || true
         sed 's/^/'"$mode"': /' "$output" >&2
         echo "$mode ended before becoming ready" >&2
         exit 1
      fi
      attempt=$((attempt + 1))
      if [ "$attempt" -ge 500 ]; then
         sed 's/^/'"$mode"': /' "$output" >&2
         echo "$mode did not become ready" >&2
         exit 1
      fi
      sleep 0.01
   done
   for second in 1 3 5; do
      sleep "$([ "$second" -eq 1 ] && echo 1 || echo 2)"
      rss=$(rss_kib "$native_pid")
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
   native_pid=$(benchmark_pid "$output" "$BENCH_PID" load)
   peak=0
   samples=0
   rss_error="$NUPP_BENCH_TEMP/load-rss-error"
   while kill -0 "$BENCH_PID" 2>/dev/null; do
      if rss=$(rss_kib "$native_pid") 2>"$rss_error"; then
         samples=$((samples + 1))
      elif kill -0 "$BENCH_PID" 2>/dev/null; then
         sed 's/^/load: /' "$rss_error" >&2
         echo "load RSS sampling failed while the benchmark was running" >&2
         exit 1
      else
         break
      fi
      if [ "$rss" -gt "$peak" ]; then
         peak=$rss
      fi
      sleep 0.05
   done
   wait "$BENCH_PID"
   BENCH_PID=
   if [ "$samples" -eq 0 ]; then
      echo "load benchmark ended without an RSS sample" >&2
      exit 1
   fi
   printf 'load peak_rss_kib=%s\n' "$peak"
}

measure_load
measure net-slow-reader
measure net-slow-writer
measure http-slow-reader
measure http-slow-writer
