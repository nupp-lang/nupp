#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture="$root/tests/dual-dialect-library"
portable_runtime=${1:-lua}
native_runtime=${NUPP_LUAJIT:-"$($root/scripts/toolchain luajit)/bin/luajit"}

(cd "$fixture" && ../../bin/nupp build --target native >/dev/null)
(cd "$fixture" && ../../bin/nupp build --compat lua51 --strict -o build/lua51 src/main.nupp src/codec.nupp >/dev/null)

native=$(LUA_PATH="$fixture/build/luajit/?.lua;;" \
    "$native_runtime" "$fixture/build/luajit/main.lua")
compatible=$(LUA_PATH="$fixture/build/lua51/?.lua;$fixture/build/lua51/src/?.lua;;" \
    "$portable_runtime" "$fixture/build/lua51/src/main.lua")
test "$native" = "$compatible"

echo "ordinary and compat-checked generation passed ($native)"
