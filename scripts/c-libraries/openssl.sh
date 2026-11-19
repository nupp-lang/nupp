# Sourced by native-libraries with verified inputs and an owned staging tree.
case "$TARGET" in
    aarch64-apple-darwin) configure=darwin64-arm64-cc ;;
    x86_64-apple-darwin) configure=darwin64-x86_64-cc ;;
    x86_64-unknown-linux-gnu) configure=linux-x86_64 ;;
    aarch64-unknown-linux-gnu) configure=linux-aarch64 ;;
    x86_64-pc-windows-msvc) configure=VC-WIN64A ;;
esac
assembly=''
# MSVC builds deliberately need no unpinned external assembler.
if [ "$SYSTEM" = windows ]; then assembly=no-asm; fi
(cd "$source"
 if [ "$SYSTEM" = darwin ]; then
    SDKROOT=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
    export SDKROOT
 fi
 CC="$CC" perl Configure "$configure" shared no-tests no-docs no-quic no-cms \
    $assembly --prefix="$install" --openssldir="$install/ssl" --libdir=lib >&2
 if [ "$SYSTEM" = windows ]; then
    nmake >&2
    nmake install_sw >&2
 else
    make -j "$JOBS" >&2
    make install_sw >&2
 fi)
license="$source/LICENSE.txt"
