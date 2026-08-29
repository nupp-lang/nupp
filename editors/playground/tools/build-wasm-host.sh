#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 BUNDLE_SHA256 OUTPUT_MJS LUA_SOURCE_DIR" >&2
  exit 2
fi

digest=$1
output=$2
lua_source=$3
script_dir=$(cd "$(dirname "$0")" && pwd)
playground=$(cd "$script_dir/.." && pwd)
repo_root=$(cd "$playground/../.." && pwd)
wasm_source="$playground/wasm"
emcc_command=${EMCC:-emcc}
wasm_malloc=${NUPP_WASM_MALLOC:-emmalloc}

if [[ ! $digest =~ ^[0-9a-f]{64}$ ]]; then
  echo "invalid compiler bundle SHA-256: $digest" >&2
  exit 2
fi
if [[ ! -f "$lua_source/lapi.c" ]]; then
  echo "Lua 5.1 source directory is incomplete: $lua_source" >&2
  exit 2
fi
if ! command -v "$emcc_command" >/dev/null 2>&1; then
  echo "Emscripten 6.0.8 is required (set EMCC or put emcc on PATH)" >&2
  exit 2
fi
version=$($emcc_command --version | sed -n '1s/.*emcc.* \([0-9][0-9.]*\).*/\1/p')
if [[ $version != 6.0.8 ]]; then
  echo "Emscripten 6.0.8 is required, found ${version:-unknown}" >&2
  exit 2
fi

mkdir -p "$(dirname "$output")"

lua_sources=()
for source in "$lua_source"/*.c; do
  case $(basename "$source") in
    lua.c|luac.c|print.c) ;;
    *) lua_sources+=("$source") ;;
  esac
done

"$emcc_command" \
  -std=c99 -O3 -flto \
  -I"$lua_source" -I"$wasm_source" \
  -DNUPP_BUNDLE_SHA256=\"$digest\" \
  "${lua_sources[@]}" \
  "$wasm_source/nupp_host.c" \
  --no-entry \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sEXPORT_NAME=createNuppPlayground \
  -sENVIRONMENT=web,worker,node \
  -sFILESYSTEM=0 \
  -sMALLOC="$wasm_malloc" \
  -sALLOW_MEMORY_GROWTH=1 \
  -sINITIAL_MEMORY=67108864 \
  -sMAXIMUM_MEMORY=268435456 \
  -sSTACK_SIZE=5242880 \
  -sEXPORTED_FUNCTIONS='["_nupp_boot","_nupp_request","_nupp_response_data","_nupp_response_size","_nupp_response_free","_nupp_last_error","_nupp_bundle_sha256","_malloc","_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["HEAPU8","UTF8ToString"]' \
  -sINCOMING_MODULE_JS_API='["locateFile","wasmBinary"]' \
  -o "$output"
