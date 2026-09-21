#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
corpus="$root/tests/lua51-compat"

(cd "$corpus" && "$root/bin/nupp" build --compat lua51 --strict >/dev/null)

if [ "$#" -eq 0 ]; then
    set -- lua5.1 lua5.2 lua5.3 lua5.4 luajit
fi

allow_missing=0
if [ "${1-}" = "--available" ]; then
    allow_missing=1
    shift
fi

ran=0
for runtime in "$@"; do
    if ! command -v "$runtime" >/dev/null 2>&1; then
        if [ "$allow_missing" -eq 1 ]; then
            echo "compatible output: $runtime unavailable"
            continue
        fi
        echo "compatible output: required runtime is missing: $runtime" >&2
        exit 1
    fi
    actual=$("$runtime" "$corpus/build/main.lua")
    test "$actual" = "lua51 compatibility corpus ok" || {
        echo "compatible output: $runtime returned: $actual" >&2
        exit 1
    }
    echo "compatible output: $runtime passed"
    ran=$((ran + 1))
    if [ "${runtime##*/}" = luajit ]; then
        actual=$(CORPUS_FILE="$corpus/build/main.lua" "$runtime" -e \
            'table.unpack=unpack; unpack=nil; dofile(assert(os.getenv("CORPUS_FILE")))')
        test "$actual" = "lua51 compatibility corpus ok" || {
            echo "compatible output: $runtime without global unpack returned: $actual" >&2
            exit 1
        }
        echo "compatible output: $runtime without global unpack passed"
    fi
done

test "$ran" -gt 0
