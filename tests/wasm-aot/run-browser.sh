#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
temporary=${RUNNER_TEMP:-/tmp}
lua_source=${NUPP_LUA51_SOURCE:-$temporary/nupp-portable-compiler/lua-5.1.5/src}
emcc_command=${NUPP_WASM_CC:-${EMCC:-emcc}}
chrome_command=${CHROME:-google-chrome}
port=${NUPP_BROWSER_TEST_PORT:-8791}
site=$(mktemp -d "${TMPDIR:-/tmp}/nupp-browser-app.XXXXXX")
server_pid=
cleanup() {
  if [[ -n $server_pid ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$site"
}
trap cleanup EXIT

if [[ ! -f "$lua_source/lapi.c" ]]; then
  echo "Lua 5.1 source directory is incomplete: $lua_source" >&2
  exit 2
fi

runtime="$site/runtime"
for case_name in plain scalar simd128 http platform derive cancel runtime-error \
    workers workers-scalar workers-simd; do
  target=app
  case $case_name in
    plain) project="$script_dir/plain-project" ;;
    scalar) project="$script_dir/project" ;;
    simd128) project="$script_dir/simd-project" ;;
    http) project="$script_dir/http-project" ;;
    platform) project="$script_dir/platform-project" ;;
    derive) project="$script_dir/derive-project" ;;
    cancel) project="$script_dir/cancel-project" ;;
    runtime-error) project="$script_dir/error-project" ;;
    workers) project="$script_dir/workers-project" ;;
    workers-scalar) project="$script_dir/workers-simd-project"; target=scalar ;;
    workers-simd) project="$script_dir/workers-simd-project"; target=simd ;;
  esac
  output="$site/$case_name"
  echo "packaging browser application: $case_name ($target)" >&2
  NUPP_WASM_CC="$emcc_command" \
  NUPP_BROWSER_RUNTIME="$runtime" \
  NUPP_LUA51_SOURCE="$lua_source" \
    "$repo/scripts/browser-app" "$project" "$target" "$output" >/dev/null
  cp "$script_dir/browser/index.html" "$output/index.html"
  cp "$script_dir/browser/smoke.mjs" "$output/smoke.mjs"
done
cp "$script_dir/browser/http-response.json" "$site/http-response.json"

cp -R "$site/scalar" "$site/missing"
node "$script_dir/remove-side-module.mjs" "$site/missing"

PORT=$port node "$repo/editors/playground/serve.mjs" "$site" >"$site/server.log" 2>&1 &
server_pid=$!
for attempt in {1..30}; do
  if curl --fail --silent "http://127.0.0.1:$port/plain/index.html" >/dev/null; then break; fi
  sleep 1
done
curl --fail --silent "http://127.0.0.1:$port/plain/index.html" >/dev/null

for case_name in plain scalar simd128 http platform derive cancel runtime-error missing \
    workers workers-scalar workers-simd; do
  case $case_name in plain) expected=none ;; *) expected=$case_name ;; esac
  CHROME="$chrome_command" node "$repo/editors/playground/tools/run-browser-smoke.mjs" \
    "http://127.0.0.1:$port/$case_name/index.html?expect=$expected" \
    >"$site/$case_name-result.json"
done

node "$script_dir/browser-summary.mjs" \
  "$site/plain-result.json" "$site/scalar-result.json" "$site/simd128-result.json" "$site/http-result.json" \
  "$site/platform-result.json" "$site/derive-result.json" "$site/cancel-result.json" \
  "$site/runtime-error-result.json" \
  "$site/missing-result.json" "$site/workers-result.json" "$site/workers-scalar-result.json" \
  "$site/workers-simd-result.json"
