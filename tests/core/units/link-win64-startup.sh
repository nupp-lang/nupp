#!/bin/sh
# Emit and cross-link the Win64 startup smoke. The PE is never launched here.
set -eu
[ "$#" -eq 3 ] || {
    printf 'usage: %s NEW_OUTPUT_DIRECTORY LIBUV_INCLUDE LIBUV_IMPORT_LIBRARY\n' "$0" >&2
    exit 2
}
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)
uv_include=$(CDPATH= cd -- "$2" && pwd)
uv_import=$(CDPATH= cd -- "$(dirname "$3")" && pwd)/$(basename "$3")
[ -r "$uv_include/uv.h" ] && [ -r "$uv_import" ]
mkdir -- "$1"
out=$(CDPATH= cd -- "$1" && pwd)
export NUPP_COMPILER_ROOT="$root"
(cd "$here" && "$root/bin/nupp" run emit-win64-call.lua "$out" page-size)
cd "$out"
x86_64-w64-mingw32-gcc -std=c11 -O2 -Wall -Wextra -Werror \
    -DUSING_UV_SHARED=1 -I"$uv_include" "$here/win64startupsmoke.c" \
    "$root/native/corebridge/uv.c" "$here/../bridge-abi-win64.S" win64-call.S \
    "$uv_import" -lws2_32 -Wl,--no-insert-timestamp -o win64-startup.exe
x86_64-w64-mingw32-objdump -p -d win64-startup.exe > win64-startup.dump
