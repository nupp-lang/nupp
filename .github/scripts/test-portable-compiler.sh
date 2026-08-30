#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
work=${RUNNER_TEMP:-/tmp}/nupp-portable-compiler
archive="$work/lua-5.1.5.tar.gz"
source="$work/lua-5.1.5"
host="$work/nupp-portable-host"
expected_json="$work/portable-compiler-reference.json"
generated_image="$work/preludeimage-source.bin"
roundtrip_image="$work/preludeimage-roundtrip.bin"
expected=2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333
luajit_root=$($root/scripts/toolchain luajit)
luajit="$luajit_root/bin/luajit"
luarocks="$($root/scripts/toolchain luarocks)/bin/luarocks"
lpeg_root=$($root/scripts/toolchain lpeg)

mkdir -p "$work"
if [ ! -f "$archive" ]; then
    curl -fsSL https://www.lua.org/ftp/lua-5.1.5.tar.gz -o "$archive"
fi
printf '%s  %s\n' "$expected" "$archive" | sha256sum -c -
if [ ! -d "$source" ]; then
    tar -xzf "$archive" -C "$work"
fi
case "$(uname -s)" in
    Darwin*) lua_target=macosx; host_libraries=-lm ;;
    *) lua_target=generic; host_libraries=-lm ;;
esac
make -C "$source" clean
make -C "$source" "$lua_target"

cd "$root"
./bin/nupp build --target compiler
# Built with the interpreter this job is about, rather than the pinned LuaJIT:
# the encoding is `%.17g` and the point of this job is that stock Lua 5.1 gets
# the same answers. Generating and hydrating under it is the check.
NUPP_PRELUDE_LUA="$source/src/lua" ./scripts/prelude-image
./bin/nupp build --target playgroundApplicationRuntime
"$luarocks" --lua-version=5.1 --tree="$root/.rocks" \
    --lua-dir="$luajit_root" install lunajson 1.2.3-1
LUA_PATH="$root/build/?.lua;$root/.rocks/share/lua/5.1/?.lua;$root/.rocks/share/lua/5.1/?/init.lua;;" \
LUA_CPATH="$lpeg_root/lib/?.so;$lpeg_root/lib/?.dll;$root/.rocks/lib/lua/5.1/?.so;;" \
    "$luajit" tests/portable-compiler/reference.lua > "$expected_json"
"$source/src/luac" -p build/playground/nupp-compiler.lua
# The bundle carries what the checker produced, so asking it for the image again
# has to give the same bytes back. `scripts/prelude-image` already checked the
# round trip; this checks that generating it twice is stable, which a committed
# file used to stand in for.
"$source/src/lua" editors/playground/tools/generate-prelude-image.lua \
    build/playground/nupp-compiler.lua "$generated_image" source
cmp build/playground/preludeimage.bin "$generated_image"
"$source/src/lua" editors/playground/tools/generate-prelude-image.lua \
    build/playground/nupp-compiler.lua "$roundtrip_image" image
cmp build/playground/preludeimage.bin "$roundtrip_image"
${CC:-cc} -std=c99 -Wall -Wextra -Werror \
    -I"$source/src" \
    tests/portable-compiler/minimal-host.c \
    "$source/src/liblua.a" $host_libraries -o "$host"
"$host" build/playground/nupp-compiler.lua \
    tests/portable-compiler/smoke.lua "$expected_json"
"$source/src/lua" tests/portable-compiler/playground-runtime.lua \
    build/playground/nupp-app-runtime.lua
