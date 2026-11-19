# Sourced by native-libraries with verified inputs and an owned staging tree.
# shortcut: the active core runs on Unix ARM64; add an MSVC recipe before
# claiming Windows core execution. Never substitute a system libffi.
[ "$SYSTEM" != windows ] || die 'libffi provisioning needs a supported Unix toolchain'
mkdir -p "$staged/build"
(cd "$staged/build"; "$source/configure" --prefix="$install" --libdir="$install/lib" \
    --disable-static --enable-shared --disable-docs CC="$CC" >&2)
make -C "$staged/build" -j "$JOBS" >&2
make -C "$staged/build" install >&2
# The artifact-relative import has one name on both supported core systems.
# This alias and the matching upstream headers enter the verified manifest.
case "$SYSTEM" in
    darwin) ln -s libffi.dylib "$install/lib/libnuppffi" ;;
    linux) ln -s libffi.so "$install/lib/libnuppffi" ;;
esac
# Reject layout/configuration drift before publishing a consumable artifact.
# Use the same compiler flags that configured the library and matching headers.
"$CC" ${CPPFLAGS:-} ${CFLAGS:-} -UNDEBUG -std=c11 -Wall -Wextra -Werror -I"$install/include" \
    "$ROOT/scripts/c-libraries/libffiprobe.c" "$install/lib/libnuppffi" \
    -Wl,-rpath,"$install/lib" -o "$staged/libffi-layout" >&2
"$staged/libffi-layout" >&2
license="$source/LICENSE"
