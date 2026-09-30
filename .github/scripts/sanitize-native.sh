#!/bin/sh

# Run the native crates' tests under one sanitizer, then the C ABI smoke tests
# against a provider built the same way.
#
#   .github/scripts/sanitize-native.sh address|thread
#
# `address` is AddressSanitizer with LeakSanitizer on, which is its default on
# Linux; `thread` is ThreadSanitizer. Both need a nightly compiler with
# rust-src (NUPP_SANITIZER_TOOLCHAIN, pinned below), because a sanitizer
# is only sound when std is instrumented too: `-Zbuild-std` rebuilds it with
# the same flags, and that in turn needs an explicit `--target`, which also
# keeps the flags off build scripts and proc macros.
#
# The C that build scripts compile is instrumented through CFLAGS: the cc
# crate reads it (the AOT runtime, ring), and so does the host's own build
# script (the LuaJIT shims). LuaJIT itself and LPeg are the pinned prebuilt
# archives and stay uninstrumented: accesses made inside them are not
# checked, and nothing they do is reported.
#
# Two crates are left out, the same two for both sanitizers:
#
# - nupp-native-gpu drives a Vulkan/Metal driver through wgpu. The driver is
#   an uninstrumented system library that races by design from ThreadSanitizer's
#   point of view, and the tests need an adapter this job does not provision.
# - nupp-native-codegen links the pinned LLVM (NUPP_LLVM_PREFIX, an hour to
#   build from source) as uninstrumented C++, and does its work on the calling
#   thread; what it would add is sanitizing LLVM, not this repository.
#
# LeakSanitizer is Linux-only. On macOS the address leg still runs, with leak
# detection off, and says so.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SANITIZER=${1:?usage: sanitize-native.sh address|thread}
SUPPRESSIONS=$ROOT/.github/sanitizers

cd "$ROOT"

# The host crate links the pinned LuaJIT and LPeg. Resolved before the
# compiler and flags below are exported, so they are the ordinary cached
# builds rather than instrumented ones under a key of their own.
NUPP_LUAJIT_PREFIX=$(./scripts/toolchain luajit)
NUPP_LPEG_PREFIX=$(./scripts/toolchain lpeg)
export NUPP_LUAJIT_PREFIX NUPP_LPEG_PREFIX

# A dated nightly, so two runs of one commit build with the same compiler and
# a report can be reproduced. Move it deliberately, like any other pin.
RUSTUP_TOOLCHAIN=${NUPP_SANITIZER_TOOLCHAIN:-nightly-2026-09-30}
RUSTUP_SKIP_UPDATE_CHECK=1
export RUSTUP_TOOLCHAIN RUSTUP_SKIP_UPDATE_CHECK
rustup toolchain install "$RUSTUP_TOOLCHAIN" --profile minimal --component rust-src >&2
TARGET=$(rustc -vV | sed -n 's/^host: //p')
CC=${NUPP_CC:-${CC:-clang}}
NUPP_CC=$CC
export CC NUPP_CC

case "$SANITIZER" in
    address)
        # rustc links its own ASan runtime, which the C compiler's
        # instrumentation would otherwise refuse by name: Apple clang pins
        # its runtime's version, and a distribution clang is a different
        # LLVM from rustc's. The instrumentation ABI itself is shared.
        flags="-fsanitize=address -fno-omit-frame-pointer -mllvm -asan-guard-against-version-mismatch=0"
        case "$(uname -s)" in
            Linux) leaks=1 ;;
            *)
                leaks=0
                printf 'sanitize-native: LeakSanitizer is unsupported on %s; leak detection is off\n' \
                    "$(uname -s)" >&2
                ;;
        esac
        ASAN_OPTIONS="detect_leaks=$leaks:detect_stack_use_after_return=1:strict_string_checks=1"
        LSAN_OPTIONS="suppressions=$SUPPRESSIONS/lsan.supp:print_suppressions=0"
        export ASAN_OPTIONS LSAN_OPTIONS
        # A leak report is only as useful as its frames, and a suppression can
        # only match a symbolized one. ASan looks for llvm-symbolizer on PATH;
        # the runner carries it under a versioned name.
        if [ -z "${ASAN_SYMBOLIZER_PATH:-}" ]; then
            for candidate in "$(command -v llvm-symbolizer 2>/dev/null)" /usr/lib/llvm-*/bin/llvm-symbolizer; do
                if [ -x "$candidate" ]; then
                    ASAN_SYMBOLIZER_PATH=$candidate
                    export ASAN_SYMBOLIZER_PATH
                fi
            done
        fi
        ;;
    thread)
        flags="-fsanitize=thread"
        TSAN_OPTIONS="suppressions=$SUPPRESSIONS/tsan.supp:halt_on_error=0:second_deadlock_stack=1:print_suppressions=0"
        export TSAN_OPTIONS
        ;;
    *)
        printf 'sanitize-native: unknown sanitizer %s\n' "$SANITIZER" >&2
        exit 2
        ;;
esac

RUSTFLAGS="-Zsanitizer=$SANITIZER -Cforce-frame-pointers=yes"
CFLAGS="$flags -g"
export RUSTFLAGS CFLAGS

# Kept apart from the ordinary target directory: every artifact here is built
# against an instrumented std, and none of it may be mistaken for a release.
CARGO_TARGET_DIR=${CARGO_TARGET_DIR:-$ROOT/build/rust/sanitize-$SANITIZER}
export CARGO_TARGET_DIR

# One run reports everything it can find. A sanitized build takes most of an
# hour, and stopping at the first report -- the first race, the first failing
# test binary, the first failing package -- left each run showing one finding
# for the next to get past. ThreadSanitizer still exits 66 at the end when it
# reported anything, and the script exits non-zero if any package failed.
FAILED=
cargo_test() {
    # Doctests are left out: rustdoc links them against the sysroot's
    # uninstrumented std, which -Zsanitizer refuses to mix.
    if ! cargo test --locked -Zbuild-std --target "$TARGET" --no-fail-fast \
        --lib --bins --tests "$@"; then
        FAILED="$FAILED $2"
    fi
}

cargo_test --package nupp-native-abi
cargo_test --package nupp-native-platform --features uuid
cargo_test --package nupp-native-runtime --features async
cargo_test --package nupp-native-files --features lane
cargo_test --package nupp-native-compression
# ThreadSanitizer on macOS defers a signal until its thread next enters an
# interceptor it counts as blocking, and kevent is not one. Tokio learns of a
# child's exit through SIGCHLD there, so every wait on a child stalls until the
# test's deadline. Linux reaps through a pidfd or epoll, which do not stall.
if [ "$SANITIZER" = thread ] && [ "$(uname -s)" = Darwin ]; then
    printf 'sanitize-native: skipping nupp-native-process: ThreadSanitizer on macOS never delivers SIGCHLD to it\n' >&2
else
    cargo_test --package nupp-native-process
fi
cargo_test --package nupp-native-net
cargo_test --package nupp-native-tls
cargo_test --package nupp-native-http
cargo_test --package nupp-native --no-default-features \
    --features compression,files,http,net,process,tls,uri,uuid
cargo_test --package nupp-native-host --no-default-features \
    --features lpeg,native-compression,native-files,native-net,native-process,native-tls,workers

# The provider exactly as scripts/test-rust-abi links it. The GPU is compiled
# in because the smoke test asserts the feature set and that invalid GPU
# handles are refused; it never opens an adapter, so no driver is loaded.
cargo build --locked -Zbuild-std --target "$TARGET" --package nupp-native \
    --no-default-features --features files,gpu,http,net,process,tls,uri,uuid --lib
DIRECTORY=$CARGO_TARGET_DIR/$TARGET/debug
# Where the sanitizer runtime comes from differs. On Linux rustc links its
# static runtime into executables only, so the C side is instrumented and
# carries the C compiler's runtime. On macOS the runtime is a dylib the
# provider already links, and a second one from the C compiler leaves its
# interceptors uninstalled, so the C side is built plain.
case "$(uname -s)" in
    Darwin)
        PROVIDER=$DIRECTORY/libnupp_native.dylib
        smoke_flags=-g
        ;;
    *)
        PROVIDER=$DIRECTORY/libnupp_native.so
        smoke_flags=$CFLAGS
        ;;
esac
TEMP=$(mktemp -d "${TMPDIR:-/tmp}/nupp-sanitize.XXXXXX")
trap 'rm -r "$TEMP"' EXIT HUP INT TERM
for smoke in abi_smoke net_abi_smoke; do
    # shellcheck disable=SC2086
    "$CC" -std=c11 -Wall -Wextra -Werror $smoke_flags \
        -I"$ROOT/native/include" "$ROOT/native/tests/$smoke.c" \
        "$PROVIDER" -Wl,-rpath,"$DIRECTORY" -o "$TEMP/$smoke"
    "$TEMP/$smoke" || FAILED="$FAILED $smoke"
done

if [ -n "$FAILED" ]; then
    printf 'sanitize-native: failed under %s:%s\n' "$SANITIZER" "$FAILED" >&2
    exit 1
fi
