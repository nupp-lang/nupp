#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
lua_source=${NUPP_LUA51_SOURCE:-${RUNNER_TEMP:-/tmp}/nupp-portable-compiler/lua-5.1.5/src}
if [[ ! -f "$lua_source/lapi.c" ]]; then
    echo "Lua 5.1 source directory is incomplete: $lua_source" >&2
    exit 2
fi
out=$(mktemp -d "${TMPDIR:-/tmp}/nupp-wasm-memory.XXXXXX")
trap 'rm -rf "$out"' EXIT
sources=()
for source in "$lua_source"/*.c; do
    case "${source##*/}" in lua.c|luac.c|print.c) continue;; esac
    sources+=("$source")
done
fixture=${2:-tests/wasm-memory/cases.lua}
common=(-O2 -I"$lua_source" -Iruntime/wasm tests/wasm-memory/main.c runtime/wasm/nupp_memory.c)
if [[ ${1:-native} == wasm ]]; then
    "${NUPP_WASM_CC:-${EMCC:-emcc}}" "${common[@]}" "${sources[@]}" \
        -sALLOW_MEMORY_GROWTH=1 -sENVIRONMENT=node -sWASM_ASYNC_COMPILATION=0 \
        --embed-file "$fixture"@/cases.lua -o "$out/memory.cjs"
    node "$out/memory.cjs" /cases.lua
else
    "${NUPP_CC:-cc}" "${common[@]}" "${sources[@]}" -lm -o "$out/memory"
    "$out/memory" "$fixture"
fi
