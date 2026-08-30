#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/scripts/compiler-pack.pins"

output=$(cygpath -u "${1:?output archive path required}")
runner_temp=$(cygpath -u "${RUNNER_TEMP:?RUNNER_TEMP is required}")
work=$runner_temp/nupp-compiler-pack-windows
archive="$work/$LLVM_MINGW_ARCHIVE"
extracted="$work/extracted"
stage="$work/stage"
cache="$work/nupp-toolchain-cache"

rm -rf "$work"
mkdir -p "$extracted" "$stage"
curl -fsSL "$LLVM_MINGW_URL" -o "$archive"
test "$(wc -c < "$archive" | tr -d ' ')" = "$LLVM_MINGW_SIZE"
printf '%s  %s\n' "$LLVM_MINGW_SHA256" "$archive" | sha256sum -c -
unzip -q "$archive" -d "$extracted"
toolchain=$(find "$extracted" -mindepth 1 -maxdepth 1 -type d | head -n 1)
test -n "$toolchain"

cc=bin/x86_64-w64-mingw32-clang.exe
cxx=bin/x86_64-w64-mingw32-clang++.exe
ar=bin/llvm-ar.exe
test -f "$toolchain/$cc"
test -f "$toolchain/$cxx"
test -f "$toolchain/$ar"
test -f "$toolchain/bin/ar.exe" || cp "$toolchain/$ar" "$toolchain/bin/ar.exe"
if test ! -f "$toolchain/bin/ranlib.exe" && test -f "$toolchain/bin/llvm-ranlib.exe"; then
  cp "$toolchain/bin/llvm-ranlib.exe" "$toolchain/bin/ranlib.exe"
fi

features=lpeg,lua-utf8,native-files,native-net,native-process,native-tls,workers
export NUPP_TOOLCHAIN_DIR="$cache"
export NUPP_CC="$toolchain/$cc"
export NUPP_CXX="$toolchain/$cxx"
export PATH="$toolchain/bin:$PATH"
host_binary=$($ROOT/scripts/toolchain host "$features")
host_dir=$(dirname "$host_binary")
prefix=$($ROOT/scripts/toolchain --prefix)

$ROOT/scripts/compiler-pack \
  x86_64-pc-windows-msvc x86_64-pc-windows-msvc \
  "llvm-mingw-$LLVM_MINGW_RELEASE+nupp-$GITHUB_SHA" windows \
  "$toolchain" "$cc" "$ar" "$host_dir" "$prefix" \
  "$stage/lib/nupp/compiler-packs"

mkdir -p "$(dirname "$output")"
stage_windows=$(cygpath -w "$stage")
output_windows=$(cygpath -w "$output")
powershell.exe -NoProfile -Command \
  "Compress-Archive -Path '$stage_windows\\*' -DestinationPath '$output_windows'"
