#!/bin/sh
# Test fixtures and the runtime, built with the system C compiler ahead of
# time -- the product's build, not the user's. Nothing here is on the path
# the component or the host runs.
#
#   oracle.<ext>   the C backend's kernels, clang/gcc -O3 (the oracle)
#   runtime.<ext>  the C backend's builders C plus the ks_rt_* shims: the
#                  host runtime the AOT code imports, and the C builders
#   runtime.o, oracle.o, main.o  the same, for the standalone executable
#
# usage: prepare.sh OUT_DIR [kernels.json]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=$1
kernels=${2:-$here/../direct-backend/kernels.json}
builders=$here/../direct-backend/builders.json
mkdir -p "$out"
CC=${CC:-cc}
extract() { python3 -c 'import json,sys; sys.stdout.write(json.load(open(sys.argv[1]))["c"])' "$1"; }
extract "$kernels" > "$out/oracle.c"
{ extract "$builders"; cat "$here/runtime/shims.c"; } > "$out/runtime.c"
flags="-std=c11 -O3 -ffp-contract=off -fno-fast-math -w"
case "$(uname -s)" in
Darwin)
  flags="$flags -mmacosx-version-min=11.0"
  $CC $flags -fPIC -dynamiclib -o "$out/oracle.dylib" "$out/oracle.c"
  $CC $flags -fPIC -dynamiclib -undefined dynamic_lookup -o "$out/runtime.dylib" "$out/runtime.c"
  # The standalone executable's pieces: objects whose only exports are what
  # the AOT code and main need, so the two C files' helpers cannot collide.
  $CC $flags -c -o "$out/runtime.full.o" "$out/runtime.c"
  $CC $flags -c -o "$out/oracle.full.o" "$out/oracle.c"
  nm -gU "$out/runtime.full.o" | awk '{print $3}' | grep -E '^_(ks_rt_|ks_register_|ks_waves$|nupp_sin$)' > "$out/runtime.exports"
  nm -gU "$out/oracle.full.o" | awk '{print $3}' | grep -E '^_ks_(map|refine|explicit_map|explicit_refine|explicit_algebraic)$' > "$out/oracle.exports"
  ld -r -exported_symbols_list "$out/runtime.exports" -o "$out/runtime.o" "$out/runtime.full.o"
  ld -r -exported_symbols_list "$out/oracle.exports" -o "$out/oracle.o" "$out/oracle.full.o"
  register=$(grep -o 'ks_register_[0-9a-f]*' "$out/runtime.c" | head -1)
  $CC -std=c11 -O2 -w -DKS_REGISTER="$register" -c -o "$out/main.o" "$here/runtime/main.c"
  ;;
Linux)
  $CC $flags -mavx2 -mfma -fPIC -shared -o "$out/oracle.so" "$out/oracle.c" -lm
  $CC $flags -fPIC -shared -o "$out/runtime.so" "$out/runtime.c" -lm
  ;;
MINGW*|MSYS*|CYGWIN*)
  $CC $flags -mavx2 -mfma -shared -o "$out/oracle.dll" "$out/oracle.c"
  $CC $flags -shared -o "$out/runtime.dll" "$out/runtime.c" -Wl,--export-all-symbols -Wl,--enable-auto-import -L"$LUAJIT_LIB" -llua51
  ;;
esac
