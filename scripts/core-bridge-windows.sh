# Sourced by scripts/core-bridge on Windows ARM64: builds the bridge and its
# guard with LLVM MinGW (MSYS2's clangarm64 environment, ahead on PATH) and
# the pinned C libraries built with it (aarch64-pc-windows-gnullvm). ROOT,
# OUT, flags, sanitize, test and die come from the caller.
#
# Windows finds a program's DLLs beside it, so the bridge's libraries are
# staged beside nupp-core.exe rather than under lib/, which holds what the
# guest loads relative to its bundle. The bridge exports every symbol, as
# -rdynamic does elsewhere: the guest resolves its C calls in the process
# by name (hostwin64.h, find_symbol). Its URI mapping uses the system's
# ICU (icu.dll, Windows 10 1903 and later), declared by the Windows SDK's
# icu.h, which NUPP_WINDOWS_SDK_INCLUDE names when it is not installed in
# the usual place.
[ "$sanitize" = 0 ] || die 'the Windows ARM64 bridge has no sanitizer build'
CC=${NUPP_CC:-clang}
case "$("$CC" -dumpmachine 2>/dev/null)" in
    aarch64-w64-windows-gnu | aarch64-w64-mingw32) ;;
    *) die 'Windows ARM64 needs an LLVM MinGW clang targeting aarch64-w64-windows-gnu' ;;
esac
NUPP_CC=$CC
export NUPP_CC
uv=$(sh "$ROOT/scripts/native-libraries" libuv) || die 'could not provision pinned libuv'
ssl=$(sh "$ROOT/scripts/native-libraries" openssl) || die 'could not provision pinned OpenSSL'
curl=$(sh "$ROOT/scripts/native-libraries" libcurl) || die 'could not provision pinned libcurl'

# The newest installed Windows SDK that declares the system ICU.
icu_header=
if [ -n "${NUPP_WINDOWS_SDK_INCLUDE:-}" ]; then
    icu_header="$NUPP_WINDOWS_SDK_INCLUDE/icu.h"
else
    kits="/c/Program Files (x86)/Windows Kits/10/Include"
    for version in $(ls "$kits" 2> /dev/null | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n); do
        [ -r "$kits/$version/um/icu.h" ] && icu_header="$kits/$version/um/icu.h"
    done
fi
[ -n "$icu_header" ] && [ -r "$icu_header" ] ||
    die 'no Windows SDK icu.h found; set NUPP_WINDOWS_SDK_INCLUDE to its um directory'

common="$ROOT/native/corebridge"
http="$ROOT/native/httpcurl"
mkdir -p "$OUT"
stage=$(mktemp -d "$OUT/.sidecars.XXXXXX")
pending=".$$.pending"
trap 'rm -rf "$stage" "$OUT"/*"$pending"' EXIT
# icu.h alone, so MinGW's own Windows headers stay ahead of the SDK's.
mkdir "$stage/icu" "$stage/notices"
cp "$icu_header" "$stage/icu/icu.h"

# The DLLs the bridge loads, and their notices, from the verified packages.
for package in "$uv" "$curl"; do
    cp -P "$package"/bin/*.dll "$stage/"
    cp -RP "$package/notices/." "$stage/notices/"
done
[ -f "$stage/libuv.dll" ] || die 'pinned libuv lacks libuv.dll'
[ -f "$stage/libcurl.dll" ] || die 'pinned libcurl lacks libcurl.dll'

defines="-DUSING_UV_SHARED=1 -DNUPP_WIN64_PROCESS -DNUPP_CORE_HTTP -DNUPP_CORE_NET -DNUPP_CORE_TLS"
defines="$defines -DNUPP_WIN64_HTTP_SYSTEM_ICU=1"
compile() {
    # shellcheck disable=SC2086 # flags and defines are lists of words
    "$CC" $flags $defines -iquote "$common" -I"$uv/include" -I"$curl/include" -I"$ssl/include" \
        -I"$stage/icu" "$@"
}
sources="$common/uv.c $common/process.c $common/winpipe.c $common/streamio.c $common/winposix.c
$common/netbridge.c $common/tcp.c $common/udp.c $common/tlsbio.c $http/transport.c $http/uriidna.c"
libraries="$uv/lib/libuv.dll.a $curl/lib/libcurl.dll.a $ssl/lib/libssl.dll.a $ssl/lib/libcrypto.dll.a
-licu -lws2_32 -lcrypt32 -lbcrypt"
link_bridge() {
    # shellcheck disable=SC2086 # sources and libraries are lists of paths
    compile -Wl,--export-all-symbols "$@" $sources $libraries
}
link_bridge -municode "$common/main.c" -o "$OUT/nupp-core$pending.exe"
link_bridge "$common/guard.c" "$ROOT/tests/core/bridgeabi.S" -o "$OUT/nupp-core-guard$pending.exe"
mkdir -p "$OUT/notices"
for file in "$stage"/*.dll "$stage"/notices/*.txt; do
    [ -f "$file" ] || continue
    relative=${file#"$stage"/}
    cp -P "$file" "$OUT/$relative$pending"
    mv -f "$OUT/$relative$pending" "$OUT/$relative"
done
mv -f "$OUT/nupp-core$pending.exe" "$OUT/nupp-core.exe"
mv -f "$OUT/nupp-core-guard$pending.exe" "$OUT/nupp-core-guard.exe"
if [ "$test" = 1 ]; then
    # The Windows contracts the x64 probes run, which are not x64 code; the
    # AAPCS64 preservation probe runs in the guard (bridgeabi.S).
    contract() {
        name=$1
        shift
        # shellcheck disable=SC2086 # flags is a list of words
        "$CC" $flags -DUSING_UV_SHARED=1 -iquote "$common" -I"$uv/include" "$@" -o "$OUT/$name$pending.exe"
        mv -f "$OUT/$name$pending.exe" "$OUT/$name.exe"
        "$OUT/$name.exe" >&2
    }
    tests="$ROOT/tests/core"
    contract nupp-loader-contracts -DNUPP_WIN64_PROCESS "$tests/bridgeloaderwin64contract.c" "$common/uv.c" \
        "$common/process.c" "$common/winpipe.c" "$common/streamio.c" "$common/winposix.c" \
        "$uv/lib/libuv.dll.a" -lws2_32 -lbcrypt
    contract nupp-process-contracts -DNUPP_WIN64_PROCESS "$tests/processwin64contract.c" "$common/process.c" \
        "$common/uv.c" "$common/winpipe.c" "$common/streamio.c" "$uv/lib/libuv.dll.a" -lws2_32
    contract nupp-tcp-contracts "$tests/tcpcontracts.c" "$common/tcp.c" "$common/streamio.c" \
        "$uv/lib/libuv.dll.a" -lws2_32
    contract nupp-net-contracts -DNUPP_CORE_NET "$tests/netbridgecontracts.c" "$common/netbridge.c" \
        "$common/tcp.c" "$common/streamio.c" "$common/udp.c" "$common/uv.c" "$uv/lib/libuv.dll.a" -lws2_32
fi
printf '%s\n' "$OUT"
