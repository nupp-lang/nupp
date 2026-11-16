#!/bin/sh
# Exact WGPU dispatch/readback through the retained Windows DX12 backend.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"
export WGPU_BACKEND=dx12
export NUPP_REQUIRE_GPU=1
export NUPP_EXPECT_GPU_BACKEND=dx12

# The verified seed and prebuilt WebGPU C library need no Rust installation.
python3 .github/scripts/test-wgpu-conformance.py
