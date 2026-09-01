#!/bin/sh
# Record public native-runtime and exact-feature build measurements without
# turning hosted-runner timing into a pass/fail threshold.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
results=${1:?usage: measure-native-runtime.sh OUTPUT_DIRECTORY}
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
   "$rustc" --version
   "$cargo" --version
   printf 'node='
   node --version
} > "$results/metadata.txt"

# The benchmark target stages public dependencies from the compiler build.
# A clean measurement runner has no ambient root build to inherit.
./bin/nupp build
bench/native-runtime/run.sh > "$results/public-boundary.txt"
bench/native-runtime/resource.sh > "$results/resources.txt"

# Use a fresh task-local target so this is a cold exact-feature provider build
# even when the compiler and host caches were restored. The second invocation
# measures the content-addressed warm lookup. These are observations, not
# acceptance limits.
features=base,filesystem,http,net,uri
exact_root=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/nupp-native-exact-$$
trap 'rm -rf "$exact_root"' EXIT HUP INT TERM

cold_started=$(now_ms)
provider=$(NUPP_RUST_BUILD_DIR="$exact_root" \
   ./scripts/toolchain native-rust "$features")
cold_finished=$(now_ms)
warm_started=$(now_ms)
warm_provider=$(NUPP_RUST_BUILD_DIR="$exact_root" \
   ./scripts/toolchain native-rust "$features")
warm_finished=$(now_ms)
[ "$provider" = "$warm_provider" ]

provider_dir=$(dirname "$provider")
provider_static=$provider_dir/libnupp_native_v2.a
[ -f "$provider" ]
[ -f "$provider_static" ]

benchmark=bench/native-runtime/build/native-runtime-benchmark
if [ -f "$benchmark.exe" ]; then
   benchmark=$benchmark.exe
fi
[ -f "$benchmark" ]
benchmark_provider=bench/native-runtime/build/lib/nupp_native_v2
if [ ! -f "$benchmark_provider" ]; then
   benchmark_provider=$(find bench/native-runtime/build/lib -maxdepth 1 -type f \
      \( -name 'nupp_native_v2.dll' -o -name 'libnupp_native_v2.so' \
         -o -name 'libnupp_native_v2.dylib' \) -print | head -n 1)
fi
[ -n "$benchmark_provider" ]

{
   printf 'features=%s\n' "$features"
   printf 'cold_ms=%s\n' "$((cold_finished - cold_started))"
   printf 'warm_ms=%s\n' "$((warm_finished - warm_started))"
   printf 'provider_dynamic_bytes=%s\n' "$(file_bytes "$provider")"
   printf 'provider_static_bytes=%s\n' "$(file_bytes "$provider_static")"
   printf 'benchmark_binary_bytes=%s\n' "$(file_bytes "$benchmark")"
   printf 'benchmark_provider_bytes=%s\n' "$(file_bytes "$benchmark_provider")"
} > "$results/exact-feature-build.txt"

printf 'native runtime measurements written to %s\n' "$results"
