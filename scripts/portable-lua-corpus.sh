#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
corpus="$root/tests/portable-corpus"
cli_build=$(mktemp -d "${TMPDIR:-/tmp}/nupp-cli-portable.XXXXXX")
cli_lua_root=$cli_build
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*) cli_lua_root=$(cygpath -m "$cli_build") ;;
esac
trap 'rm -rf "$cli_build"' EXIT HUP INT TERM

(cd "$corpus" && ../../bin/nupp build --dialect lua51 >/dev/null)
if ! (cd "$root" && ./bin/nupp build --dialect lua51 --strict -o "$cli_build" \
  tests/fixtures/cliparser.nupp src/nupp/runtime/provider/tablebuffer.nupp \
  >"$cli_build/build.log" 2>&1); then
    cat "$cli_build/build.log" >&2
    exit 1
fi
expected=$(sed -n '1p' "$corpus/expected.txt")

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
            echo "portable corpus: $runtime unavailable"
            continue
        fi
        echo "portable corpus: required runtime is missing: $runtime" >&2
        exit 1
    fi
    actual=$(LUA_PATH="$corpus/build/?.lua;;" "$runtime" "$corpus/build/setup.lua")
    if [ "$actual" != "$expected" ]; then
        echo "portable corpus: $runtime returned: $actual" >&2
        echo "portable corpus: expected: $expected" >&2
        exit 1
    fi
    case "$runtime" in
      *luajit*)
        cli_actual=$(LUA_PATH="$cli_lua_root/?.lua;$cli_lua_root/?/init.lua;$cli_lua_root/src/?.lua;$cli_lua_root/src/?/init.lua;;" \
          "$runtime" -e 'jit=nil; dofile(arg[1])' "$cli_build/tests/fixtures/cliparser.lua")
        ;;
      *)
        cli_actual=$(LUA_PATH="$cli_lua_root/?.lua;$cli_lua_root/?/init.lua;$cli_lua_root/src/?.lua;$cli_lua_root/src/?/init.lua;;" \
          "$runtime" "$cli_build/tests/fixtures/cliparser.lua")
        ;;
    esac
    if [ "$cli_actual" != "cli parser ok" ]; then
        echo "portable cli: $runtime returned: $cli_actual" >&2
        exit 1
    fi
    echo "portable corpus: $runtime passed"
    ran=$((ran + 1))
done

test "$ran" -gt 0
