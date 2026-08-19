#!/bin/sh
set -eu

# Nupp emits the syntax extensions from LuaJIT's rolling 2.1 branch. Distribution
# packages commonly carry beta3 instead, so CI builds the exact VM it is testing.
luajit_commit=1edc3e52b67eaf6ce5f809be8e17d6862594b8bc
simdjson_commit=1bcf71bd85059ab6574ea1159de9298dcc1212c5
luarocks_commit=3421bedc2ce2b64e79530bb97497531b014899a8
# The compiler parses its own doc comments with `nupp.peg`, which resolves
# native LPeg, so the module has to exist before the first build rather than
# arriving later with what `nupp doc` renders with.
lpeg_version=1.1.0-2
tool_root="$RUNNER_TEMP/nupp-ci-tools"
luajit_root="$tool_root/luajit"
luajit_install="$tool_root/luajit-install"
simdjson_root="$tool_root/simdjson"
simdjson_build="$tool_root/simdjson-build"
simdjson_install="$tool_root/simdjson-install"
luarocks_root="$tool_root/luarocks"
luarocks_install="$tool_root/luarocks-install"

git clone --filter=blob:none https://github.com/LuaJIT/LuaJIT.git "$luajit_root"
git -C "$luajit_root" checkout --detach "$luajit_commit"
if [ "$(uname -s)" = Darwin ]; then
    MACOSX_DEPLOYMENT_TARGET="$(sw_vers -productVersion | cut -d. -f1,2)"
    export MACOSX_DEPLOYMENT_TARGET
    # Every other POSIX target links the interpreter with -Wl,-E, where a Mach-O
    # executable exports nothing unless asked. A LuaRocks-built module resolves
    # the Lua API out of the process that loaded it, so LPeg arrives with an
    # undefined luaL_checkany without this.
    make -C "$luajit_root" -j2 \
        TARGET_XCFLAGS=-DLUAJIT_UNWIND_INTERNAL \
        TARGET_LDFLAGS=-Wl,-export_dynamic
else
    make -C "$luajit_root" -j2
fi
make -C "$luajit_root" install PREFIX="$luajit_install"

git clone --filter=blob:none https://github.com/simdjson/simdjson.git "$simdjson_root"
git -C "$simdjson_root" checkout --detach "$simdjson_commit"
cmake -S "$simdjson_root" -B "$simdjson_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$simdjson_install" \
    -DBUILD_SHARED_LIBS=OFF \
    -DSIMDJSON_DEVELOPER_MODE=OFF \
    -DSIMDJSON_INSTALL=ON
cmake --build "$simdjson_build" --config Release --parallel 2
cmake --install "$simdjson_build" --config Release

module_root="$GITHUB_WORKSPACE/.rocks/lib/lua/5.1"
mkdir -p "$module_root"

git clone --filter=blob:none https://github.com/luarocks/luarocks.git "$luarocks_root"
git -C "$luarocks_root" checkout --detach "$luarocks_commit"
(cd "$luarocks_root" && ./configure \
    --prefix="$luarocks_install" \
    --rocks-tree="$GITHUB_WORKSPACE/.rocks" \
    --lua-version=5.1 \
    --with-lua-bin="$luajit_install/bin" \
    --with-lua-include="$luajit_install/include/luajit-2.1" \
    --with-lua-lib="$luajit_install/lib" \
    --with-lua-interpreter=luajit \
    --force-config && make install)

"$luarocks_install/bin/luarocks" install lpeg "$lpeg_version"

pkg_config_path="$simdjson_install/lib/pkgconfig:$luajit_install/lib/pkgconfig"
printf '%s\n' "$luajit_install/bin" "$luarocks_install/bin" >> "$GITHUB_PATH"
printf 'LUA_PATH=%s/src/?.lua;;\n' "$luajit_root" >> "$GITHUB_ENV"
printf 'LUA_CPATH=%s/?.so;;\n' "$module_root" >> "$GITHUB_ENV"
printf 'PKG_CONFIG_PATH=%s\n' "$pkg_config_path" >> "$GITHUB_ENV"
if [ "$(uname -s)" = Darwin ]; then
    printf 'DYLD_LIBRARY_PATH=%s/lib\n' "$luajit_install" >> "$GITHUB_ENV"
else
    printf 'LD_LIBRARY_PATH=%s/lib\n' "$luajit_install" >> "$GITHUB_ENV"
fi

LUA_PATH="$luajit_root/src/?.lua;;" \
LUA_CPATH="$module_root/?.so;;" \
    "$luajit_install/bin/luajit" -e 'require("lpeg"); assert((nil ?? 1) == 1)'
PKG_CONFIG_PATH="$pkg_config_path" pkg-config --cflags --libs simdjson luajit
"$luarocks_install/bin/luarocks" --version
