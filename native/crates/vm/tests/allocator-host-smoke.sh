#!/bin/sh
# Build outside the workspace with an application-owned global allocator.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/nupp-allocator-host.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir "$tmp/src"
cp "$root/native/crates/vm/tests/allocator-host/main.rs" "$tmp/src/main.rs"
# Reuse the workspace's pinned dependency versions and compiled artifacts.
cp "$root/Cargo.lock" "$tmp/Cargo.lock"
cat > "$tmp/Cargo.toml" <<EOF
[package]
name = "nupp-allocator-host-acceptance"
version = "0.0.0"
edition = "2024"
[workspace]
[dependencies]
nupp-vm = { path = "$root/native/crates/vm", default-features = false, features = ["allocation-metrics"] }
[features]
allocator-mimalloc = ["nupp-vm/allocator-mimalloc"]
allocator-jemalloc = ["nupp-vm/allocator-jemalloc"]
EOF
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$root/build/rust/target}"
for allocator in system mimalloc jemalloc; do
    if [ "$allocator" = system ]; then
        cargo run --offline --release --manifest-path "$tmp/Cargo.toml"
    else
        cargo run --offline --release --manifest-path "$tmp/Cargo.toml" \
            --features "allocator-$allocator"
    fi
done
