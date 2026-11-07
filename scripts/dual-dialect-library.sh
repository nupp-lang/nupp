#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
fixture="$root/tests/integration/compat/dual-dialect"
portable_runtime=${1:-lua}
native_runtime=${NUPP_LUAJIT:-"$($root/scripts/toolchain luajit)/bin/luajit"}

(cd "$fixture" && "$root/bin/nupp" build --target native >/dev/null)
(cd "$fixture" && "$root/bin/nupp" build --target native --compat lua51 -o build/lua51 >/dev/null)

native=$(LUA_PATH="$fixture/build/luajit/?.lua;;" \
    "$native_runtime" "$fixture/build/luajit/main.lua")
compatible=$(LUA_PATH="$fixture/build/lua51/?.lua;;" \
    "$portable_runtime" "$fixture/build/lua51/main.lua")
test "$native" = "$compatible"

echo "ordinary and compat-checked generation passed ($native)"
