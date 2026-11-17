#!/bin/sh
# Build, check, and consume the pinned C CRC bundle; no Rust tool is needed.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT=${NUPP_CRC_EVIDENCE:-"$ROOT/build/crc-isal"}
mkdir -p "$OUT"
mkdir -p "$OUT/no-rust-tools"
for tool in cargo rustc rustup cargo-c; do
    printf '#!/bin/sh\necho "Unexpected Rust tool invocation" >&2\nexit 99\n' > "$OUT/no-rust-tools/$tool"
    chmod +x "$OUT/no-rust-tools/$tool"
done
PATH="$OUT/no-rust-tools:$PATH"
export PATH
prefix=$(./scripts/toolchain isal)
reused=$(NUPP_HOST_OFFLINE=1 ./scripts/toolchain isal 2> "$OUT/reuse.log")
[ "$reused" = "$prefix" ] && [ ! -s "$OUT/reuse.log" ] || { echo 'ISA-L warm reuse rebuilt' >&2; exit 1; }
# Package the verified headers, libraries, identity and notice as one unit.
mkdir -p "$OUT/package"
cp -RP "$prefix/." "$OUT/package/"
cmake -S tests/fixtures/c-libraries/crc -B "$OUT/probe" -DCMAKE_BUILD_TYPE=Release \
    -DNUPP_ISAL="$OUT/package"
cmake --build "$OUT/probe" --config Release --parallel 2
program="$OUT/probe/crc-probe"
if [ -f "$OUT/probe/Release/crc-probe.exe" ]; then program="$OUT/probe/Release/crc-probe.exe"; fi
"$program" > "$OUT/crc.txt"
# Move the consumed bundle after linking. Loader paths must work in a package,
# independently of the original cache and the link-time package path.
relocated="$OUT/relocated"
if [ -e "$relocated" ]; then rm -rf "$relocated"; fi
mv "$OUT/package" "$relocated"
shared="$OUT/probe/crc-shared-probe"
if [ -f "$OUT/probe/Release/crc-shared-probe.exe" ]; then shared="$OUT/probe/Release/crc-shared-probe.exe"; fi
PATH="$relocated/bin:$PATH" LD_LIBRARY_PATH="$relocated/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    DYLD_LIBRARY_PATH="$relocated/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" "$shared" >> "$OUT/crc.txt"
cp "$prefix/identity" "$OUT/isal.identity"
cat "$OUT/crc.txt"
