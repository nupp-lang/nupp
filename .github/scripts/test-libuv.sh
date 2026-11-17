#!/bin/sh
# Pin/cache/relocation checks against the real upstream C artifact, not the VM.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
. "$ROOT/scripts/toolchain.pins"
OUT=${NUPP_LIBUV_EVIDENCE:-"$ROOT/build/libuv"}
mkdir -p "$OUT"
OUT=$(CDPATH= cd -- "$OUT" && pwd)
# Guard the whole consumer path, including CMake's configure/build steps.
mkdir -p "$OUT/no-rust-tools"
for tool in cargo rustc rustup cargo-c; do
    printf '#!/bin/sh\necho "Unexpected Rust tool invocation" >&2\nexit 99\n' > "$OUT/no-rust-tools/$tool"
    chmod +x "$OUT/no-rust-tools/$tool"
done
PATH="$OUT/no-rust-tools:$PATH"
export PATH
began=$(date +%s)
prefix=$(./scripts/toolchain libuv)
provision=$(( $(date +%s) - began ))
began=$(date +%s)
reused=$(NUPP_HOST_OFFLINE=1 NUPP_HOST_SOURCE_DIR="$OUT/absent-source" ./scripts/toolchain libuv 2> "$OUT/reuse.log")
[ "$reused" = "$prefix" ] && [ ! -s "$OUT/reuse.log" ] || { echo 'libuv warm reuse rebuilt or changed the artifact' >&2; exit 1; }
reuse=$(( $(date +%s) - began ))
target=$(sed -n 's/^target=//p' "$prefix/identity")
cp "$prefix/identity" "$OUT/libuv.identity"
cp "$prefix/files.sha256" "$OUT/libuv-files.sha256"

# CMake's upstream export must keep finding the same headers/library after a
# prefix move. Build a consumer from that moved SDK, then move the package again.
package=$(mktemp -d "$OUT/package.XXXXXX")
cp -RP "$prefix/." "$package/"
cmake -S tests/fixtures/libuv -B "$OUT/probe" -DCMAKE_BUILD_TYPE=Release \
    -DNUPP_LIBUV="$package" -DNUPP_LIBUV_VERSION="$LIBUV_VERSION" -DNUPP_TARGET="$target" \
    -Dlibuv_DIR="$package/lib/cmake/libuv"
cmake --build "$OUT/probe" --config Release --parallel 2
cmake --install "$OUT/probe" --config Release --prefix "$package"
moved="$package-relocated"
mv "$package" "$moved"
for metadata in "$moved"/lib/pkgconfig/libuv*.pc; do
    grep -Fx 'prefix=${pcfiledir}/../..' "$metadata" > /dev/null
    grep -Fx 'libdir=${prefix}/lib' "$metadata" > /dev/null
    grep -Fx 'includedir=${prefix}/include' "$metadata" > /dev/null
done
program=./bin/libuv-probe
if [ -f "$moved/bin/libuv-probe.exe" ]; then program=./bin/libuv-probe.exe; fi
(cd "$moved"; unset LD_LIBRARY_PATH DYLD_LIBRARY_PATH; "$program") > "$OUT/abi.json"

# Refuse a different requested SDK version even if this host has system libuv.
if cmake -S tests/fixtures/libuv -B "$OUT/wrong-version" -DNUPP_LIBUV="$moved" \
    -Dlibuv_DIR="$moved/lib/cmake/libuv" -DNUPP_LIBUV_VERSION=0.0.0 -DNUPP_TARGET="$target" > "$OUT/wrong-version.log" 2>&1; then
    echo 'mismatched libuv version was accepted' >&2; exit 1
fi

# Never damage the shared cache: corruption tests use private copied entries.
badcache=$(mktemp -d "$OUT/cache.XXXXXX")
entry="$badcache/c-libraries/libuv/$(basename "$prefix")"
case "$target" in
    *darwin) shared=lib/libuv.1.0.0.dylib ;;
    *linux-gnu) shared=lib/libuv.so.1.0.0 ;;
    *windows-msvc) shared=bin/uv.dll ;;
esac
for damaged in include/uv/version.h "$shared" files.sha256; do
    mkdir -p "$entry"
    cp -RP "$prefix/." "$entry/"
    : > "$entry/$damaged"
    if NUPP_TOOLCHAIN_DIR="$badcache" NUPP_HOST_OFFLINE=1 ./scripts/toolchain libuv > "$OUT/refused.log" 2>&1; then
        echo "damaged libuv $damaged was accepted" >&2; exit 1
    fi
    grep 'corrupt cache entry' "$OUT/refused.log" > /dev/null
done
if NUPP_NATIVE_TARGET=wasm32-unknown-unknown ./scripts/toolchain libuv > "$OUT/wrong-target.log" 2>&1; then
    echo 'non-native libuv target was accepted' >&2; exit 1
fi
grep 'refusing host output' "$OUT/wrong-target.log" > /dev/null
printf '{"provisionSeconds":%s,"warmReuseSeconds":%s,"warmRebuilt":false,"relocated":true,"refusalsPassed":true}\n' \
    "$provision" "$reuse" > "$OUT/timing.json"
cat "$OUT/abi.json"
