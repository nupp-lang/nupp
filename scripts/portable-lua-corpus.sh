#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
corpus="$root/tests/portable-corpus"

(cd "$corpus" && ../../bin/nupp build --dialect lua51 >/dev/null)
expected=$(sed -n '1p' "$corpus/expected.txt")

if [ "$#" -eq 0 ]; then
    set -- lua5.1 lua5.2 lua5.3 lua5.4 luajit
fi

ran=0
for runtime in "$@"; do
    if ! command -v "$runtime" >/dev/null 2>&1; then
        echo "portable corpus: required runtime is missing: $runtime" >&2
        exit 1
    fi
    actual=$("$runtime" "$corpus/build/main.lua")
    if [ "$actual" != "$expected" ]; then
        echo "portable corpus: $runtime returned: $actual" >&2
        echo "portable corpus: expected: $expected" >&2
        exit 1
    fi
    echo "portable corpus: $runtime passed"
    ran=$((ran + 1))
done

test "$ran" -gt 0
