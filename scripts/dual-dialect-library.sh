#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture="$root/tests/dual-dialect-library"
portable_runtime=${1:-lua}
native_runtime=${NUPP_LUAJIT:-"$($root/scripts/toolchain luajit)/bin/luajit"}

(cd "$fixture" && ../../bin/nupp build --target native >/dev/null)
(cd "$fixture" && ../../bin/nupp build --target portable >/dev/null)

native=$(LUA_PATH="$fixture/build/luajit/?.lua;;" \
    "$native_runtime" "$fixture/build/luajit/main.lua")
portable=$(LUA_PATH="$fixture/build/lua51/?.lua;;" "$portable_runtime" "$fixture/build/lua51/main.lua")
test "$native" = "$portable"

grep -q '~' "$fixture/build/luajit/codec.lua"
if grep -q '__nuppBitops' "$fixture/build/luajit/codec.lua"; then
    echo "dual dialect library: LuaJIT artifact contains portable bitops" >&2
    exit 1
fi
grep -q '__nuppBitops' "$fixture/build/lua51/codec.lua"
if grep -q 'require("ffi")' "$fixture/build/lua51/codec.lua"; then
    echo "dual dialect library: Lua 5.1 artifact contains FFI struct storage" >&2
    exit 1
fi

echo "dual dialect library: LuaJIT and Lua 5.1 passed ($native)"
