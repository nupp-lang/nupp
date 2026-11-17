#!/bin/sh
# The installed, relocated provider is consumed without any Rust tool.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT="$ROOT/build/cmark-probe"
mkdir -p "$OUT"
prefix=$(./scripts/toolchain cmark)
reused=$(./scripts/toolchain cmark 2> "$OUT/reuse.log")
[ "$prefix" = "$reused" ] && [ ! -s "$OUT/reuse.log" ] || { echo 'Markdown warm cache rebuilt' >&2; exit 1; }
cmake -S tests/fixtures/markdown -B "$OUT/consumer" -DCMAKE_BUILD_TYPE=Release -DNUPP_CMARK="$prefix"
cmake --build "$OUT/consumer" --config Release --parallel 2
destination=$(mktemp -d "$OUT/relocated.XXXXXX")
cmake --install "$OUT/consumer" --config Release --prefix "$destination"
mkdir -p "$destination/lib" "$destination/notices"
case "$(uname -s)" in
    Darwin) cp "$prefix/lib/libnupp_markdown.dylib" "$destination/lib/" ;;
    MINGW*|MSYS*) cp "$prefix/bin/nupp_markdown.dll" "$destination/" ;;
    *) cp "$prefix/lib/libnupp_markdown.so" "$destination/lib/" ;;
esac
cp "$prefix/notices/cmark-gfm-LICENSE.txt" "$destination/notices/"
cp "$prefix/identity" "$OUT/markdown.identity"
cp "$prefix/files.sha256" "$OUT/markdown-files.sha256"
program="$destination/markdown-probe"
ownership="$destination/markdown-ownership"
if [ -f "$program.exe" ]; then program="$program.exe"; ownership="$ownership.exe"; fi
# CMake's install strips the build rpath. Only the relocated module is loaded.
"$ownership"
node tests/fixtures/markdown/check.mjs "$program"
