#!/bin/sh
# Compare exact-feature provider builds with and without WGPU. Hosted-runner
# timings are observations, not pass/fail thresholds.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
results=${1:?usage: measure-gpu-provider.sh OUTPUT_DIRECTORY BACKEND}
backend=${2:?usage: measure-gpu-provider.sh OUTPUT_DIRECTORY BACKEND}
case "$results" in
   /*) ;;
   *) results=$root/$results ;;
esac
mkdir -p "$results"

now_ms() {
   node -e 'process.stdout.write(String(Date.now()))'
}

file_bytes() {
   wc -c < "$1" | tr -d ' '
}

measure_provider() {
   label=$1
   features=$2
   target_root=$3

   cold_started=$(now_ms)
   provider=$(NUPP_RUST_BUILD_DIR="$target_root" \
      ./scripts/toolchain native-rust "$features")
   cold_finished=$(now_ms)
   warm_started=$(now_ms)
   warm_provider=$(NUPP_RUST_BUILD_DIR="$target_root" \
      ./scripts/toolchain native-rust "$features")
   warm_finished=$(now_ms)
   [ "$provider" = "$warm_provider" ]

   provider_static=$(dirname "$provider")/libnupp_native_v2.a
   [ -f "$provider" ]
   [ -f "$provider_static" ]

   {
      printf '%s_features=%s\n' "$label" "$features"
      printf '%s_cold_ms=%s\n' "$label" "$((cold_finished - cold_started))"
      printf '%s_warm_ms=%s\n' "$label" "$((warm_finished - warm_started))"
      printf '%s_dynamic_bytes=%s\n' "$label" "$(file_bytes "$provider")"
      printf '%s_static_bytes=%s\n' "$label" "$(file_bytes "$provider_static")"
   } >> "$results/exact-feature-gpu.txt"
}

cd "$root"
channel=$(sed -n 's/^channel = "\([^"]*\)"$/\1/p' rust-toolchain.toml)
rust_toolchain=$channel
case "$(uname -s 2>/dev/null || printf unknown)" in
   MINGW*|MSYS*|CYGWIN*) rust_toolchain=$channel-x86_64-pc-windows-gnu ;;
esac
export RUSTUP_TOOLCHAIN=$rust_toolchain RUSTUP_SKIP_UPDATE_CHECK=1
cargo=$(rustup which cargo)
rustc=$(rustup which rustc)

{
   printf 'commit=%s\n' "${GITHUB_SHA:-$(git rev-parse HEAD)}"
   printf 'runner=%s/%s\n' "${RUNNER_OS:-$(uname -s)}" "${RUNNER_ARCH:-$(uname -m)}"
   printf 'backend=%s\n' "$backend"
   "$rustc" --version
   "$cargo" --version
   printf 'node='
   node --version
} > "$results/metadata.txt"
: > "$results/exact-feature-gpu.txt"

# Each union gets an independent empty target directory. That makes both first
# runs cold even if the conformance step populated the job's shared Rust cache;
# the repeated command then measures the content-addressed warm lookup.
# Use the shell's own temporary path spelling. RUNNER_TEMP is a native drive
# path on Windows and is not reliably consumable by POSIX tools in Git Bash.
exact_root=${TMPDIR:-/tmp}/nupp-gpu-exact-$$
trap 'rm -rf "$exact_root"' EXIT HUP INT TERM
non_gpu_features=base,files,http,net,process,tls,uri,uuid
gpu_features=base,files,gpu,http,net,process,tls,uri,uuid

measure_provider non_gpu "$non_gpu_features" "$exact_root/non-gpu"
measure_provider gpu "$gpu_features" "$exact_root/gpu"

printf 'GPU provider measurements written to %s\n' "$results"
