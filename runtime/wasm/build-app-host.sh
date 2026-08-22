#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 OUTPUT_MJS LUA_SOURCE_DIR" >&2
  exit 2
fi

output=$1
lua_source=$2
script_dir=$(cd "$(dirname "$0")" && pwd)
emcc_command=$(printenv EMCC || true)
if [[ -z $emcc_command ]]; then emcc_command=emcc; fi

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
  echo "Emscripten 6.0.8 is required, found $version" >&2
  exit 2
fi

mkdir -p "$(dirname "$output")"
set --
for source in "$lua_source"/*.c; do
  case $(basename "$source") in
    lua.c|luac.c|print.c) ;;
    *) set -- "$@" "$source" ;;
  esac
done

"$emcc_command" \
  -std=c99 -O3 -flto \
  -I"$lua_source" -I"$script_dir" \
  "$@" \
  "$script_dir/nupp_memory.c" \
  "$script_dir/nupp_app_host.c" \
  --no-entry \
  -sMAIN_MODULE=2 \
  -sAUTOLOAD_DYLIBS=0 \
  -sMODULARIZE=1 \
  -sEXPORT_ES6=1 \
  -sEXPORT_NAME=createNuppAppHost \
  -sENVIRONMENT=web,worker,node \
  -sFILESYSTEM=0 \
  -sALLOW_MEMORY_GROWTH=1 \
  -sINITIAL_MEMORY=33554432 \
  --pre-js "$script_dir/dylink-runtime.js" \
  -sEXPORTED_FUNCTIONS='["_nupp_app_boot","_nupp_app_run","_nupp_app_last_error","_nupp_wasm_pointer_address","_luaL_checknumber","_luaL_error","_lua_type","_lua_toboolean","_lua_getfield","_lua_setfield","_lua_createtable","_lua_pushnumber","_lua_pushboolean","_lua_pushcclosure","_lua_settop","_malloc","_free"]' \
  -sEXPORTED_RUNTIME_METHODS='["HEAPU8","UTF8ToString","loadDynamicLibrary"]' \
  -sINCOMING_MODULE_JS_API='["locateFile","wasmBinary"]' \
  -o "$output"
