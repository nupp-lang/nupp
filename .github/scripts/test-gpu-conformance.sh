#!/bin/sh
# Exact GPU dispatch/readback through the pinned software Vulkan device.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
sdl=$($root/scripts/toolchain sdl)
icd=$($root/scripts/toolchain swiftshader)
luajit=$($root/scripts/toolchain luajit)/bin/luajit
bench=$root/bench/sdl-gpu-spike

export NUPP_SDL_ROOT="$sdl"
export VK_ICD_FILENAMES="$icd"
# Unlike `dummy`, SDL's offscreen driver exposes Vulkan hooks while still
# needing no display. The GPU backend rejects a video driver without them
# before it can discover the pinned SwiftShader device.
export SDL_VIDEODRIVER=offscreen
export LD_LIBRARY_PATH="$sdl/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

"$root/bin/nupp" build
(
    cd "$bench"
    "$root/bin/nupp" build --target typed
)

typed=$bench/build/typed
export LUA_PATH="$typed/?.lua;$typed/?/init.lua;$root/.rocks/share/lua/5.1/?.lua;$root/.rocks/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$root/.rocks/lib/lua/5.1/?.so;;"
export NUPP_GPU_LIBRARY="$typed/lib/nupp_native"
export GEMM_M=64 GEMM_N=64 GEMM_K=64

"$luajit" "$bench/gemm-api.lua"
