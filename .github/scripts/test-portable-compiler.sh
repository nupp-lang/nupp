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
luajit="$($root/scripts/toolchain luajit)/bin/luajit"

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
    *) lua_target=linux; host_libraries="-lm -ldl" ;;
esac
make -C "$source" clean
make -C "$source" "$lua_target"

cd "$root"
./bin/nupp build --target compiler
LUA_PATH="$root/build/?.lua;$root/.rocks/share/lua/5.1/?.lua;$root/.rocks/share/lua/5.1/?/init.lua;;" \
LUA_CPATH="$root/.rocks/lib/lua/5.1/?.so;;" \
    "$luajit" tests/portable-compiler/reference.lua > "$expected_json"
./bin/nupp build --target playgroundCompiler
"$source/src/luac" -p build/playground/nupp-compiler.lua
"$source/src/lua" editors/playground/tools/generate-prelude-image.lua \
    build/playground/nupp-compiler.lua "$generated_image" source
cmp src/nupp/compiler/preludeimage.bin "$generated_image"
"$source/src/lua" editors/playground/tools/generate-prelude-image.lua \
    build/playground/nupp-compiler.lua "$roundtrip_image" image
cmp src/nupp/compiler/preludeimage.bin "$roundtrip_image"
${CC:-cc} -std=c99 -Wall -Wextra -Werror \
    -I"$source/src" \
    tests/portable-compiler/minimal-host.c \
    "$source/src/liblua.a" $host_libraries -o "$host"
"$host" build/playground/nupp-compiler.lua \
    tests/portable-compiler/smoke.lua "$expected_json"
