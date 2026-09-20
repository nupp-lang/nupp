#!/usr/bin/env bash
# Choose two real dialects; Apple's gcc alias is not GCC. Windows Clang must
# target the same GNU ABI and sysroot as the LuaJIT import library.
set -euo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
clang=$(command -v clang)
gcc=$(command -v gcc)
case $(uname -s) in
  Darwin)
    gcc=
    for candidate in gcc-16 gcc-15 gcc-14 gcc-13 gcc-12; do
      if command -v "$candidate" >/dev/null 2>&1; then
        gcc=$(command -v "$candidate")
        break
      fi
    done
    if [[ -z "$gcc" ]]; then
      brew install gcc
      gcc=$(find "$(brew --prefix gcc)/bin" -name 'gcc-[0-9]*' -type f | sort | tail -1)
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    mkdir -p build/simd-tools
    export NUPP_SIMD_CLANG=$(cygpath -m "$clang")
    export NUPP_SIMD_GNU_ROOT=$(cygpath -m "$(dirname "$gcc")/..")
    export NUPP_SIMD_GNU_TARGET=$("$gcc" -dumpmachine)
    [[ "$NUPP_SIMD_GNU_TARGET" == *mingw* ]]
    "$gcc" -std=c11 -O2 -Wall -Wextra -Werror tests/simd/clang-mingw.c -o build/simd-tools/clang-mingw.exe
    clang=$(cygpath -m "$repo/build/simd-tools/clang-mingw.exe")
    gcc=$(cygpath -m "$gcc")
    for name in NUPP_SIMD_CLANG NUPP_SIMD_GNU_ROOT NUPP_SIMD_GNU_TARGET; do
      printf '%s=%s\n' "$name" "${!name}" >> "$GITHUB_ENV"
    done
    ;;
esac
"$clang" --version
"$gcc" --version
if "$gcc" --version | grep -iq clang; then
  echo 'The selected GCC is a Clang alias' >&2
  exit 1
fi
case ${NUPP_SIMD_COMPILER_FAMILY:-both} in
  clang) selected=$clang ;;
  gcc) selected=$gcc ;;
  both) selected="$clang,$gcc" ;;
  *) echo 'Unknown SIMD compiler family' >&2; exit 2 ;;
esac
printf 'NUPP_SIMD_COMPILERS=%s\n' "$selected" >> "$GITHUB_ENV"
