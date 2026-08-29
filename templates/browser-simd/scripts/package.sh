#!/bin/sh
set -eu

nupp_source=$${NUPP_SOURCE:-$${NUPP_COMPILER_ROOT:-}}
if [ -z "$nupp_source" ] || [ ! -x "$nupp_source/scripts/browser-app" ]; then
    echo "browser package: set NUPP_SOURCE to a Nupp source checkout" >&2
    exit 2
fi

runtime=$${NUPP_BROWSER_RUNTIME:-"$PWD/dist/browser-runtime"}
NUPP_BROWSER_RUNTIME="$runtime" "$nupp_source/scripts/browser-app" \
    . scalar dist/browser/scalar
NUPP_BROWSER_RUNTIME="$runtime" "$nupp_source/scripts/browser-app" \
    . simd dist/browser/simd
cp web/index.html web/app.mjs dist/browser/
