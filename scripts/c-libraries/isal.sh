# Sourced by native-libraries with verified inputs and an owned staging tree.
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
set --
if [ "$SYSTEM" = windows ]; then set -- -G Ninja; fi
cmake -S "$ROOT/native/crc" -B "$staged/build" \
    "$@" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DCMAKE_INSTALL_PREFIX="$install" -DISAL_SOURCE="$source" >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
license="$source/LICENSE"
cp "$ROOT/host/notices/ISA-L-CRC-LICENSE.txt" "$install/notices/ISA-L-CRC-LICENSE.txt"
