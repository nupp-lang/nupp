#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
. "$ROOT/scripts/compiler-pack.pins"

output=${1:?output archive path required}
work=${RUNNER_TEMP:?RUNNER_TEMP is required}/nupp-compiler-pack-linux
archive="$work/$LLVM_LINUX_ARCHIVE"
extracted="$work/extracted"
toolchain="$work/toolchain"
stage="$work/stage"
cache="$work/nupp-toolchain-cache"

rm -rf "$work"
mkdir -p "$extracted" "$toolchain/bin" "$toolchain/lib" "$stage"
curl -fsSL "$LLVM_LINUX_URL" -o "$archive"
test "$(wc -c < "$archive" | tr -d ' ')" = "$LLVM_LINUX_SIZE"
printf '%s  %s\n' "$LLVM_LINUX_SHA256" "$archive" | sha256sum -c -
tar -xJf "$archive" -C "$extracted"
llvm=$(find "$extracted" -mindepth 1 -maxdepth 1 -type d | head -n 1)
test -n "$llvm"

cp "$llvm/bin/clang" "$toolchain/bin/clang"
cp "$llvm/bin/ld.lld" "$toolchain/bin/ld.lld"
cp "$llvm/bin/llvm-ar" "$toolchain/bin/llvm-ar"
cp -R "$llvm/lib/clang" "$toolchain/lib/clang"
for library in "$llvm"/lib/libLLVM.so* "$llvm"/lib/libclang-cpp.so*; do
  test -e "$library" || continue
  cp -L "$library" "$toolchain/lib/"
done

# Keep the compiler relocatable even on a minimal glibc installation. The OS
# loader and libc remain platform facilities, just as they are for Nupp itself;
# LLVM's other shared dependencies travel with the compiler.
runtime_packages="$work/runtime-packages"
: > "$runtime_packages"
{
  for executable in "$toolchain/bin/clang" "$toolchain/bin/ld.lld" "$toolchain/bin/llvm-ar"; do
    ldd "$executable" 2>/dev/null || true
  done
} | awk '/=> \/[^ ]+/ {print $3}' | sort -u | while read -r library; do
  case "$(basename "$library")" in
    libc.so.*|libm.so.*|libpthread.so.*|libdl.so.*|ld-linux-*) continue ;;
  esac
  cp -L "$library" "$toolchain/lib/"
  dpkg-query -S "$library" 2>/dev/null | head -n 1 | cut -d: -f1 >> "$runtime_packages" || true
done

sysroot="$toolchain/sysroot"
mkdir -p "$sysroot/usr/include" "$sysroot/usr/lib/x86_64-linux-gnu" \
  "$sysroot/usr/lib/gcc" "$sysroot/lib/x86_64-linux-gnu" "$sysroot/lib64"
find /usr/include -maxdepth 1 -type f -name '*.h' -exec cp -L {} "$sysroot/usr/include/" \;
for directory in arpa asm-generic linux net netinet netpacket protocols rpc scsi sys x86_64-linux-gnu; do
  test ! -e "/usr/include/$directory" || cp -RL "/usr/include/$directory" "$sysroot/usr/include/"
done
cp -RL /usr/lib/gcc/x86_64-linux-gnu "$sysroot/usr/lib/gcc/"
for object in /usr/lib/x86_64-linux-gnu/*.o; do
  test ! -f "$object" || cp -L "$object" "$sysroot/usr/lib/x86_64-linux-gnu/"
done
for pattern in libc libm libpthread libdl librt libutil libresolv; do
  for library in /usr/lib/x86_64-linux-gnu/$pattern.so* /usr/lib/x86_64-linux-gnu/$pattern.a; do
    test ! -e "$library" || cp -L "$library" "$sysroot/usr/lib/x86_64-linux-gnu/"
  done
  for library in /lib/x86_64-linux-gnu/$pattern.so*; do
    test ! -e "$library" || cp -L "$library" "$sysroot/lib/x86_64-linux-gnu/"
  done
done
for library in /usr/lib/x86_64-linux-gnu/libc_nonshared.a \
  /usr/lib/x86_64-linux-gnu/libmvec.a /usr/lib/x86_64-linux-gnu/libmvec.so*; do
  test ! -e "$library" || cp -L "$library" "$sysroot/usr/lib/x86_64-linux-gnu/"
done
cp -L /lib64/ld-linux-x86-64.so.2 "$sysroot/lib64/ld-linux-x86-64.so.2"
cp -L /lib/x86_64-linux-gnu/libgcc_s.so.1 "$sysroot/lib/x86_64-linux-gnu/libgcc_s.so.1"

build_cc="$work/nupp-cc"
build_cxx="$work/nupp-cxx"
cat > "$build_cc" <<SH
#!/bin/sh
exec "$toolchain/bin/clang" --target=x86_64-unknown-linux-gnu \
  --sysroot="$toolchain/sysroot" --gcc-toolchain="$toolchain/sysroot/usr" \
  --ld-path="$toolchain/bin/ld.lld" "\$@"
SH
cat > "$build_cxx" <<SH
#!/bin/sh
exec "$toolchain/bin/clang" --driver-mode=g++ --target=x86_64-unknown-linux-gnu \
  --sysroot="$toolchain/sysroot" --gcc-toolchain="$toolchain/sysroot/usr" \
  --ld-path="$toolchain/bin/ld.lld" "\$@"
SH
ln -s llvm-ar "$toolchain/bin/ar"
chmod +x "$build_cc" "$build_cxx"

mkdir -p "$toolchain/notices"
llvm_license=
while IFS= read -r candidate; do
  if grep -q 'The LLVM Project is under the Apache License' "$candidate"; then
    llvm_license=$candidate
    break
  fi
done < <(find "$llvm" -type f \( -iname LICENSE -o -iname LICENSE.TXT \) | sort)
test -n "$llvm_license"
cp "$llvm_license" "$toolchain/notices/LLVM-LICENSE.txt"
cp /usr/share/doc/libc6/copyright "$toolchain/notices/glibc-copyright.txt"
cp /usr/share/doc/linux-libc-dev/copyright "$toolchain/notices/linux-libc-dev-copyright.txt"
sort -u "$runtime_packages" | while read -r package; do
  test -z "$package" || test ! -f "/usr/share/doc/$package/copyright" || \
    cp "/usr/share/doc/$package/copyright" "$toolchain/notices/runtime-$package-copyright.txt"
done

features=lpeg,lua-utf8,native-files,native-net,native-process,native-tls,workers
export NUPP_TOOLCHAIN_DIR="$cache"
export NUPP_CC="$build_cc"
export NUPP_CXX="$build_cxx"
export PATH="$toolchain/bin:$PATH"
host_binary=$($ROOT/scripts/toolchain host "$features")
host_dir=$(dirname "$host_binary")
prefix=$($ROOT/scripts/toolchain --prefix)

NUPP_PACK_BUILD_CC="$build_cc" $ROOT/scripts/compiler-pack \
  x86_64-unknown-linux-gnu x86_64-unknown-linux-gnu \
  "llvm-$LLVM_VERSION+ubuntu-24.04+nupp-$GITHUB_SHA" linux \
  "$toolchain" bin/clang bin/llvm-ar "$host_dir" "$prefix" \
  "$stage/lib/nupp/compiler-packs"

mkdir -p "$(dirname "$output")"
tar -czf "$output" -C "$stage" .
