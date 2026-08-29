#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
temporary=${RUNNER_TEMP:-/tmp}
lua_source=${NUPP_LUA51_SOURCE:-$temporary/nupp-portable-compiler/lua-5.1.5/src}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
port=${NUPP_BROWSER_TEMPLATE_PORT:-8792}
work=$(mktemp -d "${TMPDIR:-/tmp}/nupp-browser-templates.XXXXXX")
server_pid=

cleanup() {
  if [[ -n $server_pid ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

if [[ ! -f "$lua_source/lapi.c" ]]; then
  echo "Lua 5.1 source directory is incomplete: $lua_source" >&2
  exit 2
fi

plain="$work/plain-project"
simd="$work/simd-project"
runtime="$work/runtime"
site="$work/site"
"$repo/bin/nupp" init browser "$plain" --name browser-example --yes >/dev/null
"$repo/bin/nupp" init browser-simd "$simd" --name browser-simd-example --yes >/dev/null

for project in "$plain" "$simd"; do
  (
    cd "$project"
    NUPP_SOURCE="$repo" \
    NUPP_BROWSER_RUNTIME="$runtime" \
    NUPP_LUA51_SOURCE="$lua_source" \
    NUPP_WASM_CC="$emcc_command" \
      "$repo/bin/nupp" task package >/dev/null
  )
done

mkdir -p "$site"
cp -R "$plain/dist/browser" "$site/plain"
cp -R "$simd/dist/browser" "$site/simd"

PORT=$port node "$repo/editors/playground/serve.mjs" "$site" \
  >"$work/server.log" 2>&1 &
server_pid=$!
for attempt in {1..30}; do
  if curl --fail --silent "http://127.0.0.1:$port/plain/index.html" >/dev/null; then
    break
  fi
  sleep 1
done
curl --fail --silent "http://127.0.0.1:$port/plain/index.html" >/dev/null

CHROME="${CHROME:-google-chrome}" node \
  "$repo/editors/playground/tools/run-browser-smoke.mjs" \
  "http://127.0.0.1:$port/plain/index.html" >"$work/plain.json"
CHROME="${CHROME:-google-chrome}" node \
  "$repo/editors/playground/tools/run-browser-smoke.mjs" \
  "http://127.0.0.1:$port/simd/index.html" >"$work/simd.json"
CHROME="${CHROME:-google-chrome}" node \
  "$repo/editors/playground/tools/run-browser-smoke.mjs" \
  "http://127.0.0.1:$port/simd/index.html?scalar" >"$work/scalar.json"

node "$script_dir/summary.mjs" \
  "$work/plain.json" "$work/simd.json" "$work/scalar.json"
