#!/bin/sh

# One retained-platform gate for the Rust-owned native boundary. This is kept
# narrower than the Nupp suite: provider stress lives in the owning Rust crates,
# the aggregate ABI smoke crosses the generated C header, and hostembeddingtest
# consumes each production host artifact from C.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
FEATURES=lpeg,native-files,native-net,native-process,native-tls,workers
HOST_FEATURES=lpeg,native-files,native-net,native-process,native-tls,workers

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

# The host crate compiles its protected Lua stack shims and links LPeg at build
# time. Name the same pinned prerequisites that production host builds use.
NUPP_LUAJIT_PREFIX=$(./scripts/toolchain luajit)
NUPP_LPEG_PREFIX=$(./scripts/toolchain lpeg)
export NUPP_LUAJIT_PREFIX NUPP_LPEG_PREFIX

"$CARGO" test --locked --package nupp-native-files --features lane
"$CARGO" test --locked --package nupp-native-process
"$CARGO" test --locked --package nupp-native-net
"$CARGO" test --locked --package nupp-native-tls
"$CARGO" test --locked --package nupp-native-host --no-default-features \
    --features "$HOST_FEATURES"

./scripts/test-rust-abi

# Build these before the suite so an unavailable artifact is a gate failure,
# not a platform skip. The suite then links and runs the static embedding SDK,
# dynamic embedding SDK, and statically relinked application host.
host=$(./scripts/toolchain host "$FEATURES")
sdk=$(./scripts/toolchain host-library "$FEATURES")
[ -f "$host" ]
[ -f "$sdk/libnupp.a" ]
[ -f "$sdk/link.json" ]
grep -F '"features": "lpeg,native-files,native-net,native-process,native-tls,workers"' \
    "$sdk/link.json" >/dev/null
case "$(uname -s 2>/dev/null || printf unknown)" in
    MINGW*|MSYS*|CYGWIN*)
        [ -f "$sdk/nupp.dll" ]
        [ -f "$sdk/libnupp.dll.a" ]
        ;;
    Darwin) [ -f "$sdk/libnupp.dylib" ] ;;
    *) [ -f "$sdk/libnupp.so" ] ;;
esac

TEMP=$(mktemp -d "${TMPDIR:-/tmp}/nupp-native-platform.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT HUP INT TERM
cat > "$TEMP/host.lua" <<'LUA'
assert(__nuppHost.hostFeatures.lpeg)
assert(__nuppHost.hostFeatures["native-files"])
assert(__nuppHost.hostFeatures["native-net"])
assert(__nuppHost.hostFeatures["native-process"])
assert(__nuppHost.hostFeatures["native-tls"])
assert(require("lpeg").P("rust-native-gate"):match("rust-native-gate") == 17)
LUA
"$host" "$TEMP/host.lua"

./bin/nupp test --jobs=1 hostembeddingtest
