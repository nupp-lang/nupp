#!/bin/sh
# Exact WGPU dispatch/readback through the retained Windows DX12 backend.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"
channel=$(sed -n 's/^channel = "\([^"]*\)"$/\1/p' rust-toolchain.toml)
rust_toolchain=$channel-x86_64-pc-windows-gnu
export RUSTUP_TOOLCHAIN=$rust_toolchain RUSTUP_SKIP_UPDATE_CHECK=1
cargo=$(rustup which cargo)
RUSTC=$(rustup which rustc)
RUSTDOC=$(rustup which rustdoc)
export RUSTC RUSTDOC

export WGPU_BACKEND=dx12
export NUPP_REQUIRE_GPU=1
export NUPP_EXPECT_GPU_BACKEND=dx12

# First cross the Rust provider boundary with a small WGSL compute kernel.
"$cargo" test -p nupp-native-gpu adapter_compute_round_trip_when_available \
    --locked -- --nocapture

# Then cross the public Nupp API with compiler-emitted SPIR-V and compare the
# GPU result against the AOT CPU body emitted from the same source.
"$root/bin/nupp" build
bench=$root/bench/wgpu-spike
(
    cd "$bench"
    "$root/bin/nupp" build --target typed
)

luajit=$($root/scripts/toolchain luajit)/bin/luajit
typed=$bench/build/typed
lua_root=$(cygpath -m "$root")
lua_typed=$(cygpath -m "$typed")
export LUA_PATH="$lua_typed/?.lua;$lua_typed/?/init.lua;$lua_root/build/?.lua;$lua_root/.rocks/share/lua/5.1/?.lua;$lua_root/.rocks/share/lua/5.1/?/init.lua;;"
export LUA_CPATH="$lua_root/.rocks/lib/lua/5.1/?.dll;;"
export NUPP_NATIVE_V2_LIBRARY="$lua_typed/lib/nupp_native_v2"
export GEMM_M=64 GEMM_N=64 GEMM_K=64

"$luajit" "$bench/gemm-api.lua"
