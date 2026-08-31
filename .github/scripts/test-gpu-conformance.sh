#!/bin/sh
# Exact WGPU dispatch/readback through the pinned software Vulkan device.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"
icd=$($root/scripts/toolchain swiftshader)
luajit=$($root/scripts/toolchain luajit)/bin/luajit
bench=$root/bench/wgpu-spike

export VK_ICD_FILENAMES="$icd"
export WGPU_BACKEND=vulkan
export NUPP_REQUIRE_GPU=1
export NUPP_EXPECT_GPU_BACKEND=vulkan
export NUPP_EXPECT_GPU_ADAPTER=SwiftShader

# Adapter absence is a failure in conformance, not an optional unit-test skip.
cargo test -p nupp-native-gpu adapter_compute_round_trip_when_available \
    --locked -- --nocapture

"$root/bin/nupp" build
(
    cd "$bench"
    "$root/bin/nupp" build --target typed
)

typed=$bench/build/typed
export LUA_PATH="$typed/?.lua;$typed/?/init.lua;$root/.rocks/share/lua/5.1/?.lua;$root/.rocks/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$root/.rocks/lib/lua/5.1/?.so;;"
export NUPP_NATIVE_V2_LIBRARY="$typed/lib/nupp_native_v2"
export GEMM_M=64 GEMM_N=64 GEMM_K=64

"$luajit" "$bench/gemm-api.lua"
