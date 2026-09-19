#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
corpus="$root/tests/lua51-compat"
runtime=${1:-lua5.1}
command -v "$runtime" >/dev/null 2>&1 || {
    echo "compatibility corpus: required stock Lua 5.1 interpreter is missing: $runtime" >&2
    exit 1
}
"$runtime" -e 'assert(_VERSION == "Lua 5.1" and jit == nil, "stock Lua 5.1 is required")'
for level in 0 1 2; do
    (cd "$corpus" && "$root/bin/nupp" build -O"$level")
    actual=$("$runtime" "$corpus/build/main.lua")
    test "$actual" = "lua51 compatibility corpus ok" || {
        echo "compatibility corpus: unexpected result at -O$level: $actual" >&2
        exit 1
    }
done
echo "compatibility corpus: stock Lua 5.1 passed at -O0, -O1 and -O2"
