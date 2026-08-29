#!/bin/sh
# Fetch one pinned LuaLS source tree and run Nupp's annotation importer over every
# annotated Lua file. This is deliberately an explicit task: it uses the network and
# tracks upstream compatibility, neither of which belongs in the hermetic test suite.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
REVISION=7a73c7889c1ec981dfd76fba38f5096379f62f99
DIGEST=a08362765968e6de99cbdcb6dff93acf8c693ac09100e11cbf644a2b12e96a87
CACHE_ROOT="$ROOT/build/corpus/luals"
ARCHIVE="$CACHE_ROOT/$REVISION.tar.gz"
TREE="$CACHE_ROOT/$REVISION"
COMPLETE="$TREE/.complete"

mkdir -p "$CACHE_ROOT"
if [ ! -f "$COMPLETE" ]; then
    if [ ! -f "$ARCHIVE" ]; then
        echo "downloading LuaLS $REVISION" >&2
        curl -fsSL "https://codeload.github.com/LuaLS/lua-language-server/tar.gz/$REVISION" \
            -o "$ARCHIVE.tmp"
        mv "$ARCHIVE.tmp" "$ARCHIVE"
    fi
    ACTUAL=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
    if [ "$ACTUAL" != "$DIGEST" ]; then
        echo "LuaLS archive checksum mismatch: expected $DIGEST, got $ACTUAL" >&2
        exit 1
    fi
    rm -rf "$TREE"
    mkdir -p "$TREE"
    tar -xzf "$ARCHIVE" -C "$TREE" --strip-components=1
    printf '%s\n' "$DIGEST" > "$COMPLETE"
fi

exec luajit "$ROOT/scripts/annotated-lua-corpus.lua" "$TREE"
