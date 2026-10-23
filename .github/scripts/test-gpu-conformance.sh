#!/bin/sh
# Exact WGPU dispatch/readback through CI's software Vulkan device.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
cd "$root"
icd=${NUPP_GPU_ICD:?NUPP_GPU_ICD must name the CI-provided Vulkan ICD manifest}
[ -f "$icd" ] || { printf 'missing Vulkan ICD manifest: %s\n' "$icd" >&2; exit 1; }

export VK_ICD_FILENAMES="$icd"
export WGPU_BACKEND=vulkan
export NUPP_REQUIRE_GPU=1
export NUPP_EXPECT_GPU_BACKEND=vulkan
export NUPP_EXPECT_GPU_ADAPTER=llvmpipe

# Adapter absence is a failure in conformance, not an optional unit-test skip.
cargo test -p nupp-native-gpu adapter_compute_round_trip_when_available \
    --locked -- --nocapture
