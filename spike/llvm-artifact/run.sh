#!/bin/bash
# Every check and measurement, on the platform it runs on. The component and
# the host are already built; LLVM is not on any path the host reads.
#
# usage: run.sh COMPONENT HOST OUT_DIR
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
component=$1 host=$2 out=$3
mkdir -p "$out"
case "$(uname -s)" in
Darwin) ext=dylib; kernels=$here/../direct-backend/kernels.json ;;
Linux) ext=so; kernels=$here/../direct-backend/kernels-avx2.json ;;
*) ext=dll; kernels=$here/../direct-backend/kernels-avx2.json ;;
esac
luajit=$(cd "$root" && ./scripts/toolchain luajit)
case $ext in
dylib) lj=$luajit/lib/libluajit-5.1.dylib ;;
so) lj=$luajit/lib/libluajit-5.1.so ;;
dll) lj=$luajit/bin/lua51.dll ;;
esac
fixtures=$out/fixtures
LUAJIT_LIB=$luajit/lib "$here/prepare.sh" "$fixtures" "$kernels"
native() { if [ $ext = dll ]; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
args=(--kernels "$(native "$kernels")" --builders "$(native "$here/../direct-backend/builders.json")"
      --component "$(native "$component")" --luajit "$(native "$lj")" --runtime "$(native "$fixtures/runtime.$ext")")
if [ $ext = dll ]; then
  args+=(--import lua_=lua51.dll --import luaL_=lua51.dll --import ks_rt_=runtime.dll --import '*=msvcrt.dll')
fi
status=0
{ uname -a; uptime 2>/dev/null || true; } | tee "$out/machine.txt"
echo "== check"
"$host" check "${args[@]}" --cache "$(native "$out/cache")" --oracle "$(native "$fixtures/oracle.$ext")" --verify 2>&1 | tee "$out/check.txt" || status=1
echo "== check, instruction selectors"
for isel in fast global; do
  "$host" check "${args[@]}" --cache "$(native "$out/cache")" --oracle "$(native "$fixtures/oracle.$ext")" --verify --isel $isel > "$out/check-$isel.txt" 2>&1 || status=1
  grep -E 'failures|DIFFER|contract' "$out/check-$isel.txt"
done
echo "== bench"
for isel in dag fast global; do
  "$host" bench "${args[@]}" --cache "$(native "$out/cache-bench")" --cold --runs 21 --isel $isel > "$out/cold-$isel.json" || status=1
done
"$host" bench "${args[@]}" --cache "$(native "$out/cache-bench")" --warm --runs 21 > "$out/warm.json" || status=1
cat "$out/cold-dag.json" "$out/warm.json"
echo "== run time"
"$host" time "${args[@]}" --cache "$(native "$out/cache")" --oracle "$(native "$fixtures/oracle.$ext")" --variants dag,fast,global 2>&1 | tee "$out/runtime.txt" || status=1
ls -l "$out"/cache/*/ | tee "$out/cache-listing.txt"
exit $status
