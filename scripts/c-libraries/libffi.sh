# Sourced by native-libraries with verified inputs and an owned staging tree.
# The core runs on ARM64 Unix and on Windows ARM64 with LLVM MinGW. Never
# substitute a system libffi.
[ "$SYSTEM" != windows ] || [ "$TARGET" = aarch64-pc-windows-gnullvm ] ||
    die 'libffi provisioning needs a Unix or Windows ARM64 LLVM MinGW toolchain'
mkdir -p "$staged/build"
if [ "$TARGET" = aarch64-pc-windows-gnullvm ]; then
    # Autotools runs in MSYS2's shell (native-libraries, msys2).
    msys2 "cd '$staged/build' && '$source/configure' --host=aarch64-w64-mingw32 --prefix='$install' \
        --libdir='$install/lib' --disable-static --enable-shared --disable-docs --disable-symvers CC='$CC' >&2 \
        && make -j $JOBS >&2 && make install >&2" || die 'libffi build failed'
else
    (cd "$staged/build"; "$source/configure" --prefix="$install" --libdir="$install/lib" \
        --disable-static --enable-shared --disable-docs CC="$CC" >&2)
    make -C "$staged/build" -j "$JOBS" >&2
    make -C "$staged/build" install >&2
fi
# The artifact-relative import has one name on every core system; Windows
# appends .dll to a name without an extension, so its file carries one.
# This alias and the matching upstream headers enter the verified manifest.
case "$SYSTEM" in
    darwin) ln -s libffi.dylib "$install/lib/libnuppffi" ;;
    linux) ln -s libffi.so "$install/lib/libnuppffi" ;;
    windows)
        set -- "$install"/bin/libffi*.dll
        [ "$#" -eq 1 ] && [ -f "$1" ] || die 'libffi installed no single DLL'
        cp "$1" "$install/lib/libnuppffi.dll"
        ;;
esac
# Reject layout/configuration drift before publishing a consumable artifact.
# Use the same compiler flags that configured the library and matching headers.
if [ "$SYSTEM" = windows ]; then
    "$CC" ${CPPFLAGS:-} ${CFLAGS:-} -UNDEBUG -std=c11 -Wall -Wextra -Werror -I"$install/include" \
        "$ROOT/scripts/c-libraries/libffiprobe.c" "$install/lib/libffi.dll.a" -o "$staged/libffi-layout.exe" >&2
    cp "$install/lib/libnuppffi.dll" "$staged/$(basename "$1")"
    "$staged/libffi-layout.exe" >&2
else
    "$CC" ${CPPFLAGS:-} ${CFLAGS:-} -UNDEBUG -std=c11 -Wall -Wextra -Werror -I"$install/include" \
        "$ROOT/scripts/c-libraries/libffiprobe.c" "$install/lib/libnuppffi" \
        -Wl,-rpath,"$install/lib" -o "$staged/libffi-layout" >&2
    "$staged/libffi-layout" >&2
fi
license="$source/LICENSE"
