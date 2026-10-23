#!/bin/sh

# One retained-platform gate for the Rust-owned native boundary. This is kept
# narrower than the Nupp suite: provider stress lives in the owning Rust crates.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)

cd "$ROOT"

channel=$(sed -n 's/^channel = "\([^"]*\)"$/\1/p' rust-toolchain.toml)
rust_toolchain=$channel
case "$(uname -s 2>/dev/null || printf unknown)" in
    MINGW*|MSYS*|CYGWIN*)
        rust_toolchain=$channel-x86_64-pc-windows-gnu
        NUPP_CC=${NUPP_CC:-gcc}
        export CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER=$NUPP_CC
        if [ -z "${NUPP_TEST_BASH:-}" ] || [ -z "${NUPP_TEST_SH:-}" ]; then
            bash_path=$(command -v bash)
            sh_path=$(dirname "$bash_path")/sh.exe
            [ -f "$sh_path" ]
            NUPP_TEST_BASH=${NUPP_TEST_BASH:-$(cygpath -w "$bash_path")}
            NUPP_TEST_SH=${NUPP_TEST_SH:-$(cygpath -w "$sh_path")}
        fi
        export NUPP_TEST_BASH NUPP_TEST_SH
        ;;
    *) NUPP_CC=${NUPP_CC:-${CC:-cc}} ;;
esac
export NUPP_CC RUSTUP_TOOLCHAIN=$rust_toolchain RUSTUP_SKIP_UPDATE_CHECK=1
CARGO=${NUPP_CARGO:-$(rustup which cargo)}
RUSTC=${NUPP_RUSTC:-$(rustup which rustc)}
RUSTDOC=$(rustup which rustdoc)
export RUSTC RUSTDOC

"$CARGO" test --locked --package nupp-native-files --features lane
"$CARGO" test --locked --package nupp-native-checksum
"$CARGO" test --locked --package nupp-native-compression
"$CARGO" test --locked --package nupp-native-process
"$CARGO" test --locked --package nupp-native-net
"$CARGO" test --locked --package nupp-native-tls
