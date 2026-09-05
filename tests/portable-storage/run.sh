#!/usr/bin/env bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
project=$(mktemp -d "${TMPDIR:-/tmp}/nupp-portable-storage.XXXXXX")
trap 'rm -rf "$project"' EXIT
mkdir "$project/src"
cp "$repo/tests/portable-storage/project/nupp.lua" "$project/nupp.lua"
cp -RL "$repo/tests/portable-storage/project/src/." "$project/src/"
(cd "$project" && "$repo/bin/nupp" build --target app)
"$repo/tests/wasm-memory/run.sh" "${1:-wasm}" "$project/dist/app.lua"
