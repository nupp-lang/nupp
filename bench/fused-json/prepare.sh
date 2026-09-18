#!/bin/sh
# Copies the tree's fused JSON decoder here under a second module name.
#
# Two edits, both mechanical and both in the signature only. The module name
# changes so the copy can sit beside the original in one build. And every
# `borrows source: string | Buffer` parameter becomes `source: string`,
# because the generated ahead-of-time wrapper for a string-or-buffer parameter
# does not check: the wrapper hands its source to a registered builder through
# an untyped call, and a borrow may not cross one. See
# results/arm64-macos-fused-decode.md. The benchmark decodes strings, so the
# narrower parameter measures the same bodies.
set -eu

cd "$(dirname "$0")"
source=../../src/nupp/codec/json/internal/decoder/fused.nupp
target=src/nupp/codec/json/internal/decoder/fusedbench.nupp

mkdir -p "$(dirname "$target")"
perl -0pe 's/^module nupp\.codec\.json\.internal\.decoder\.fused$/module nupp.codec.json.internal.decoder.fusedbench/m;
           s/\n    borrows source: string \| Buffer,/\n    source: string,/g;
           s/_simd\.paddedBytesU8\(/_simd.paddedStringU8(/g' \
   "$source" > "$target"

if grep -q 'borrows source' "$target"; then
   echo "prepare: a borrows source parameter survived the rewrite" >&2
   exit 1
fi
if ! grep -q '^module nupp\.codec\.json\.internal\.decoder\.fusedbench$' "$target"; then
   echo "prepare: the module name was not rewritten" >&2
   exit 1
fi
