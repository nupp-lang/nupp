# Sourced by native-libraries with verified inputs and an owned staging tree.
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
# The Windows ARM64 core bridge links its libraries statically, so its one
# executable finds none beside it; guests still load the DLL.
static=OFF
if [ "$TARGET" = aarch64-pc-windows-gnullvm ]; then static=ON; fi
set --
case "$TARGET" in
    x86_64-pc-windows-gnu | aarch64-pc-windows-gnullvm) set -- -G Ninja ;;
    x86_64-pc-windows-msvc) set -- -G "Visual Studio 17 2022" -A x64 ;;
esac
cmake "$@" -S "$source" -B "$staged/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_INSTALL_PREFIX="$install" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_STATIC="$static" -DZLIB_BUILD_SHARED=ON >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
license="$source/LICENSE"
