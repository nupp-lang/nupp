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

# Cross the Rust provider boundary with a small WGSL compute kernel. The public
# Nupp API waits on the VM GPU provider, which LuaJIT's used to stand in for.
"$cargo" test -p nupp-native-gpu adapter_compute_round_trip_when_available \
    --locked -- --nocapture
