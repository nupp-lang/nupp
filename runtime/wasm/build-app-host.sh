#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 OUTPUT_MJS LUA_SOURCE_DIR LPEG_SOURCE_DIR" >&2
  exit 2
fi

output=$1
lua_source=$2
lpeg_source=$3
script_dir=$(cd "$(dirname "$0")" && pwd)
emcc_command=$(printenv EMCC || true)
if [[ -z $emcc_command ]]; then emcc_command=emcc; fi

if [[ ! -f "$lua_source/lapi.c" ]]; then
  echo "Lua 5.1 source directory is incomplete: $lua_source" >&2
  exit 2
fi
if [[ ! -f "$lpeg_source/lpvm.c" ]]; then
  echo "LPeg source directory is incomplete: $lpeg_source" >&2
  exit 2
fi
if ! command -v "$emcc_command" >/dev/null 2>&1; then
  echo "Emscripten 6.0.8 is required (set EMCC or put emcc on PATH)" >&2
  exit 2
fi
version=$("$emcc_command" --version | sed -n '1s/.*emcc.* \([0-9][0-9.]*\).*/\1/p')
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

# LPeg, linked in rather than loaded. A materialized PEG matcher whose graph no
# specialization template covers runs on LPeg, and a browser has no loadable C
# module to require, so the engine has to be part of the host or those matchers
# have nowhere to run. The six files are LPeg's own build list.
for unit in lpvm lpcap lptree lpcode lpprint lpcset; do
  set -- "$@" "$lpeg_source/$unit.c"
done

# Side modules call this public Lua 5.1 surface directly. Pointer kernels use
# only the small registration subset; Lua-builder entries additionally allocate
# strings, userdata and tables while keeping every unfinished value rooted on
# the VM stack.
exported_functions='[
  "_nupp_app_boot",
  "_nupp_app_initialize",
  "_nupp_app_start",
  "_nupp_app_start_managed",
  "_nupp_app_resume",
  "_nupp_app_cancel",
  "_nupp_app_status",
  "_nupp_app_payload_data",
  "_nupp_app_payload_size",
  "_nupp_app_last_error",
  "_nupp_wasm_lease_address",
  "_nupp_wasm_lease_size",
  "_nupp_wasm_release_lease",
  "_nupp_wasm_pointer_address",
  "_lua_checkstack",
  "_lua_gettop",
  "_luaL_checknumber",
  "_luaL_checklstring",
  "_luaL_buffinit",
  "_luaL_addlstring",
  "_luaL_pushresult",
  "_lua_toboolean",
  "_lua_tonumber",
  "_lua_tolstring",
  "_lua_objlen",
  "_lua_topointer",
  "_lua_rawequal",
  "_lua_getmetatable",
  "_lua_createtable",
  "_lua_pushnumber",
  "_lua_pushboolean",
  "_lua_pushnil",
  "_lua_pushlightuserdata",
  "_lua_pushlstring",
  "_lua_newuserdata",
  "_lua_touserdata",
  "_lua_pushvalue",
  "_lua_concat",
  "_lua_replace",
  "_lua_insert",
  "_lua_remove",
  "_lua_settop",
  "_lua_setmetatable",
  "_lua_type",
  "_lua_pushcclosure",
  "_lua_rawseti",
  "_lua_rawgeti",
  "_lua_rawget",
  "_lua_rawset",
  "_lua_next",
  "_lua_getfield",
  "_lua_setfield",
  "_lua_call",
  "_lua_equal",
  "_luaL_error",
  "_malloc",
  "_free"
]'

"$emcc_command" \
  -std=c99 -O3 -flto \
  -I"$lua_source" -I"$lpeg_source" -I"$script_dir" \
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
  -sMAXIMUM_MEMORY=268435456 \
  --pre-js "$script_dir/dylink-runtime.js" \
  -sEXPORTED_FUNCTIONS="$exported_functions" \
  -sEXPORTED_RUNTIME_METHODS='["HEAPU8","UTF8ToString","loadDynamicLibrary"]' \
  -sINCOMING_MODULE_JS_API='["locateFile","wasmBinary"]' \
  -o "$output"
