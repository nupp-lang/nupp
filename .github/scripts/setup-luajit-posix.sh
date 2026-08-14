#!/bin/sh
set -eu

# Nupp emits the syntax extensions from LuaJIT's rolling 2.1 branch. Distribution
# packages commonly carry beta3 instead, so CI builds the exact VM it is testing.
luajit_commit=1edc3e52b67eaf6ce5f809be8e17d6862594b8bc
cjson_commit=5ce46a80b10ef9d380a45c9e6cff9ecffbe71ebb
luarocks_commit=3421bedc2ce2b64e79530bb97497531b014899a8
# The compiler parses its own doc comments with `nupp.peg`, which resolves
# native LPeg, so the module has to exist before the first build rather than
# arriving later with what `nupp doc` renders with.
lpeg_version=1.1.0-2
tool_root="$RUNNER_TEMP/nupp-ci-tools"
luajit_root="$tool_root/luajit"
cjson_root="$tool_root/lua-cjson"
cjson_build="$tool_root/cjson-build"
luarocks_root="$tool_root/luarocks"
luarocks_install="$tool_root/luarocks-install"

git clone --filter=blob:none https://github.com/LuaJIT/LuaJIT.git "$luajit_root"
git -C "$luajit_root" checkout --detach "$luajit_commit"
if [ "$(uname -s)" = Darwin ]; then
    MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1,2)"
    export MACOSX_DEPLOYMENT_TARGET
    make -C "$luajit_root" -j2 TARGET_XCFLAGS=-DLUAJIT_UNWIND_INTERNAL
else
    make -C "$luajit_root" -j2
fi

git clone --filter=blob:none https://github.com/openresty/lua-cjson.git "$cjson_root"
git -C "$cjson_root" checkout --detach "$cjson_commit"
cmake -S "$cjson_root" -B "$cjson_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DLUA_INCLUDE_DIR="$luajit_root/src" \
    -DLUA_LIBRARY="$luajit_root/src/libluajit.a"
cmake --build "$cjson_build" --config Release --parallel 2

module_root="$GITHUB_WORKSPACE/.rocks/lib/lua/5.1"
mkdir -p "$module_root"
cp "$cjson_build/cjson.so" "$module_root/cjson.so"

git clone --filter=blob:none https://github.com/luarocks/luarocks.git "$luarocks_root"
git -C "$luarocks_root" checkout --detach "$luarocks_commit"
(cd "$luarocks_root" && ./configure \
    --prefix="$luarocks_install" \
    --rocks-tree="$GITHUB_WORKSPACE/.rocks" \
    --lua-version=5.1 \
    --with-lua-bin="$luajit_root/src" \
    --with-lua-include="$luajit_root/src" \
    --with-lua-lib="$luajit_root/src" \
    --with-lua-interpreter=luajit \
    --force-config && make install)

"$luarocks_install/bin/luarocks" install lpeg "$lpeg_version"

printf '%s\n' "$luajit_root/src" "$luarocks_install/bin" >> "$GITHUB_PATH"
printf 'LUA_PATH=%s/src/?.lua;;\n' "$luajit_root" >> "$GITHUB_ENV"
printf 'LUA_CPATH=%s/?.so;;\n' "$module_root" >> "$GITHUB_ENV"

LUA_PATH="$luajit_root/src/?.lua;;" \
LUA_CPATH="$module_root/?.so;;" \
    "$luajit_root/src/luajit" -e 'require("cjson"); require("lpeg"); assert((nil ?? 1) == 1)'
"$luarocks_install/bin/luarocks" --version
