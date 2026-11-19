#!/bin/sh
# Host-only smoke: emit, cross-link and inspect a Win64 PE image. No target
# executable is launched. Uses the existing MinGW cross compiler.
set -eu
[ "$#" -eq 1 ] || { printf 'usage: %s NEW_OUTPUT_DIRECTORY\n' "$0" >&2; exit 2; }
here=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../../.." && pwd)
mkdir -- "$1"
out=$(CDPATH= cd -- "$1" && pwd)
export NUPP_COMPILER_ROOT="$root"
(cd "$here" && "$root/bin/nupp" run emit-win64-call.lua "$out")
cd "$out"
x86_64-w64-mingw32-gcc -std=c11 -Wall -Wextra -Werror \
    "$here/win64callsmoke.c" "$here/../bridge-abi-win64.S" win64-call.S \
    -o win64-call.exe
x86_64-w64-mingw32-objdump -p -d win64-call.exe > win64-call.dump
