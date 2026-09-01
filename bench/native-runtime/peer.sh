#!/bin/sh

# Start the benchmark's Node peers with bounded, diagnosable readiness. Git
# Bash rounds very short sleeps up dramatically on hosted Windows runners, so
# use whole-second polling rather than treating a subsecond sleep count as a
# deadline. Bash owns the readiness and diagnostic paths; Node crosses the
# boundary only with one stdout protocol record after both listeners bind.
start_native_benchmark_peer() {
   peer_temp=$1
   peer_ready="$peer_temp/server.ready"
   peer_log="$peer_temp/server.log"
   SERVER_PID=

   : > "$peer_ready"
   : > "$peer_log"
   node server.mjs > "$peer_ready" 2> "$peer_log" &
   SERVER_PID=$!

   peer_second=0
   peer_reason="did not report readiness within 30 seconds"
   while [ "$peer_second" -lt 30 ]; do
      if [ -s "$peer_ready" ]; then
         peer_record=$(tr -d '\r\n' < "$peer_ready")
         set -- $peer_record
         if [ "$#" -eq 3 ] && [ "$1" = READY ]; then
            case "$2" in
               ''|*[!0-9]*) ;;
               *) case "$3" in
                  ''|*[!0-9]*) ;;
                  *)
                     if [ "$2" -ge 1 ] && [ "$2" -le 65535 ] \
                        && [ "$3" -ge 1 ] && [ "$3" -le 65535 ]; then
                        NUPP_BENCH_HTTP_PORT=$2
                        NUPP_BENCH_NET_PORT=$3
                        return 0
                     fi
                     ;;
               esac ;;
            esac
         fi
         peer_reason="reported malformed readiness"
         break
      fi
      if ! kill -0 "$SERVER_PID" 2>/dev/null; then
         peer_reason="exited before readiness"
         break
      fi
      peer_second=$((peer_second + 1))
      [ "$peer_second" -ge 30 ] || sleep 1
   done

   peer_state=live
   if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      peer_status=0
      wait "$SERVER_PID" 2>/dev/null || peer_status=$?
      SERVER_PID=
      peer_state="exited with status $peer_status"
   fi
   printf 'native runtime benchmark: HTTP/TCP peer %s (%s)\n' \
      "$peer_reason" "$peer_state" >&2
   if [ -s "$peer_ready" ]; then
      printf 'peer readiness: ' >&2
      tr -d '\r' < "$peer_ready" >&2
      printf '\n' >&2
   fi
   if [ -s "$peer_log" ]; then
      sed 's/^/peer: /' "$peer_log" >&2
   fi
   return 1
}

stop_native_benchmark_peer() {
   [ -z "${SERVER_PID:-}" ] || kill "$SERVER_PID" 2>/dev/null || true
   [ -z "${SERVER_PID:-}" ] || wait "$SERVER_PID" 2>/dev/null || true
   SERVER_PID=
}
