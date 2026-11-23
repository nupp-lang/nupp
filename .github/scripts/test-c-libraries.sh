#!/bin/sh
# Real upstream C ABI/capability checks; no Rust tools or Nupp bootstrap.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT=${NUPP_C_LIBRARY_EVIDENCE:-"$ROOT/build/c-libraries"}
mkdir -p "$OUT"
node --test tests/tools/toolchain/clibraries.test.mjs
sh .github/scripts/test-crc-isal.sh
# libyaml serves only the native core, which runs on ARM64; its recipe runs the
# layout probe (scripts/c-libraries/libyamlprobe.c) before publishing.
case "$(sh scripts/host-machine)" in
    Linux:aarch64|Linux:arm64|Darwin:arm64)
        yaml=$(./scripts/toolchain libyaml)
        reused=$(NUPP_HOST_OFFLINE=1 ./scripts/toolchain libyaml 2> "$OUT/libyaml-reuse.log")
        [ "$reused" = "$yaml" ] && [ ! -s "$OUT/libyaml-reuse.log" ] || { echo "libyaml warm reuse rebuilt" >&2; exit 1; }
        cp "$yaml/identity" "$OUT/libyaml.identity"
        ;;
esac
began=$(date +%s)
zlib=$(./scripts/toolchain zlib)
openssl=$(./scripts/toolchain openssl)
libcurl=$(./scripts/toolchain libcurl)
provision=$(( $(date +%s) - began ))
began=$(date +%s)
for component in zlib openssl libcurl; do
    case "$component" in zlib) prefix=$zlib ;; openssl) prefix=$openssl ;; libcurl) prefix=$libcurl ;; esac
    reused=$(./scripts/toolchain "$component" 2> "$OUT/reuse.log")
    [ "$reused" = "$prefix" ] && [ ! -s "$OUT/reuse.log" ] || { echo 'warm reuse rebuilt or changed an artifact' >&2; exit 1; }
done
reuse=$(( $(date +%s) - began ))
printf '{"provisionSeconds":%s,"warmReuseSeconds":%s,"warmRebuilt":false}\n' "$provision" "$reuse" > "$OUT/timing.json"
target=$(sed -n 's/^target=//p' "$zlib/identity")
for prefix in "$openssl" "$libcurl"; do
    [ "$(sed -n 's/^target=//p' "$prefix/identity")" = "$target" ] || { echo 'dependency target mismatch' >&2; exit 1; }
done
cmake -S tests/fixtures/c-libraries -B "$OUT/probe" -DCMAKE_BUILD_TYPE=Release \
    -DNUPP_ZLIB="$zlib" -DNUPP_OPENSSL="$openssl" -DNUPP_CURL="$libcurl" -DNUPP_TARGET="$target"
cmake --build "$OUT/probe" --config Release --parallel 2
program="$OUT/probe/c-library-probe"
if [ -f "$OUT/probe/Release/c-library-probe.exe" ]; then program="$OUT/probe/Release/c-library-probe.exe"; fi
PATH="$libcurl/bin:$openssl/bin:$zlib/bin:$PATH" "$program" > "$OUT/abi.json"
for component in zlib openssl libcurl; do
    case "$component" in zlib) prefix=$zlib ;; openssl) prefix=$openssl ;; libcurl) prefix=$libcurl ;; esac
    # Identities contain only public source/configuration digests and target,
    # never local paths, environment dumps, credentials or transcripts.
    cp "$prefix/identity" "$OUT/$component.identity"
done
cat "$OUT/abi.json"
# SQLite: its own probe, against the one prefix the core binds.
sqlite=$(./scripts/toolchain sqlite)
cmake -S tests/fixtures/c-libraries/sqlite -B "$OUT/sqlite-probe" -DCMAKE_BUILD_TYPE=Release -DNUPP_SQLITE="$sqlite"
cmake --build "$OUT/sqlite-probe" --config Release --parallel 2
program="$OUT/sqlite-probe/sqlite-probe"
if [ -f "$OUT/sqlite-probe/Release/sqlite-probe.exe" ]; then program="$OUT/sqlite-probe/Release/sqlite-probe.exe"; fi
PATH="$sqlite/bin:$PATH" "$program" > "$OUT/sqlite.json"
cp "$sqlite/identity" "$OUT/sqlite.identity"
cat "$OUT/sqlite.json"
