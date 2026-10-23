#!/bin/sh

# Run the native crates' tests under one sanitizer.
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
# crate reads it (the AOT runtime, ring).
#
# One crate is left out, the same one for both sanitizers: nupp-native-gpu
# drives a Vulkan/Metal driver through wgpu. The driver is an uninstrumented
# system library that races by design from ThreadSanitizer's point of view, and
# the tests need an adapter this job does not provision.
#
# LeakSanitizer is Linux-only. On macOS the address leg still runs, with leak
# detection off, and says so.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
SANITIZER=${1:?usage: sanitize-native.sh address|thread}
SUPPRESSIONS=$ROOT/.github/sanitizers

cd "$ROOT"


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
if [ -n "$FAILED" ]; then
    printf 'sanitize-native: failed under %s:%s\n' "$SANITIZER" "$FAILED" >&2
    exit 1
fi
