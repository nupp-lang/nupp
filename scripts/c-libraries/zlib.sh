# Sourced by native-libraries with verified inputs and an owned staging tree.
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
set --
if [ "$TARGET" = x86_64-pc-windows-gnu ]; then set -- -G Ninja; fi
cmake "$@" -S "$source" -B "$staged/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_INSTALL_PREFIX="$install" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DZLIB_BUILD_TESTING=OFF -DZLIB_BUILD_STATIC=OFF -DZLIB_BUILD_SHARED=ON >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
license="$source/LICENSE"
