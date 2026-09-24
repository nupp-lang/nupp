#!/bin/bash
# The pinned LLVM for the component: 23.1.1 from the release tarball (the
# digest Homebrew pins), MinSizeRel, three targets, lld, nothing optional.
# The same configuration as the size-built tree in LLVM.md.
#
# usage: build-llvm.sh BUILD_DIR [extra cmake args...]
#   LLVM_SRC  an extracted source tree; fetched and verified when unset
#   JOBS      parallel jobs (default: all cores)
set -euo pipefail
url=https://github.com/llvm/llvm-project/releases/download/llvmorg-23.1.1/llvm-project-23.1.1.src.tar.xz
sha=ebe9be46fe8756d58c5b198ffad0fa2a766257add81a4dc52179bfacc7888ee6
build=$1; shift
mkdir -p "$build"
if [ -z "${LLVM_SRC:-}" ]; then
  top=$(cd "$build/.." && pwd)
  tar="$top/llvm-project-23.1.1.src.tar.xz"
  [ -f "$tar" ] || curl -fsSL -o "$tar" "$url"
  got=$( (sha256sum "$tar" 2>/dev/null || shasum -a 256 "$tar") | cut -d' ' -f1)
  [ "$got" = "$sha" ] || { echo "digest mismatch: $got" >&2; exit 1; }
  # Only what the build reads: llvm, cmake, third-party, libc (configure
  # fails without it), lld, and libunwind's headers (lld's Mach-O driver).
  # mlgo-utils holds symlinks MSYS2 cannot create; nothing builds from it.
  (cd "$top" && tar -xJf "$tar" --exclude='*/mlgo-utils' llvm-project-23.1.1.src/{llvm,cmake,third-party,libc,lld,libunwind/include})
  LLVM_SRC="$top/llvm-project-23.1.1.src"
fi
jobs=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || nproc)}
start=$(date +%s)
cmake -G Ninja -S "$LLVM_SRC/llvm" -B "$build" \
  -DCMAKE_BUILD_TYPE=MinSizeRel \
  -DLLVM_TARGETS_TO_BUILD="AArch64;X86;WebAssembly" \
  -DLLVM_ENABLE_PROJECTS=lld -DLLD_BUILD_TOOLS=OFF \
  -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_TERMINFO=OFF -DLLVM_ENABLE_Z3_SOLVER=OFF \
  -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_BUILD_TOOLS=OFF -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_INCLUDE_UTILS=OFF -DLLVM_ENABLE_BINDINGS=OFF \
  "$@" > "$build/configure.log"
configured=$(date +%s)
# llvm-config is a tool, outside `all` with LLVM_BUILD_TOOLS off.
ninja -C "$build" -j"$jobs" all llvm-config > "$build/build.log"
done_=$(date +%s)
echo "configure $((configured - start)) s, build $((done_ - configured)) s, $jobs jobs"
