# Build unchanged upstream and the separately owned public-hook extension.
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
set --
if [ "$TARGET" = x86_64-pc-windows-gnu ]; then
    make=$(command -v gmake || command -v make || command -v mingw32-make) || die 'MinGW Markdown needs GNU make'
    set -- -G 'Unix Makefiles' "-DCMAKE_MAKE_PROGRAM=$make"
fi
cmake "$@" -S "$ROOT/native/markdown" -B "$staged/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMARK_SOURCE="$source" \
    -DCMAKE_INSTALL_PREFIX="$install" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_NAME_DIR=@rpath >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
license="$source/COPYING"
