# Sourced by native-libraries with verified inputs and an owned staging tree.
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
set --
if [ "$TARGET" = x86_64-pc-windows-msvc ]; then
    # The generator defaults to the OS architecture, even under vcvars64.
    set -- -G "Visual Studio 17 2022" -A x64
fi
cmake "$@" -S "$source" -B "$staged/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_INSTALL_PREFIX="$install" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DBUILD_TESTING=OFF -DLIBUV_BUILD_SHARED=ON -DLIBUV_BUILD_TESTS=OFF -DLIBUV_BUILD_BENCH=OFF >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
# Upstream's .pc files embed the temporary install prefix; keep SDK moves valid.
for metadata in "$install"/lib/pkgconfig/libuv*.pc; do
    sed -e 's|^prefix=.*|prefix=${pcfiledir}/../..|' \
        -e 's|^libdir=.*|libdir=${prefix}/lib|' \
        -e 's|^includedir=.*|includedir=${prefix}/include|' "$metadata" > "$metadata.relocated"
    mv "$metadata.relocated" "$metadata"
done
license="$source/LICENSE"
cmp "$source/LICENSE-extra" "$ROOT/host/notices/libuv-LICENSE-extra.txt" || die 'libuv extra notice differs from verified source'
cp "$source/LICENSE-extra" "$install/notices/libuv-LICENSE-extra.txt"
# LICENSE-extra names these external parts; keep their full source notices too.
sed -n '1,/ \*\//p' "$source/include/uv/tree.h" > "$install/notices/libuv-tree-LICENSE.txt"
sed -n '1,/ \*\//p' "$source/src/inet.c" > "$install/notices/libuv-inet-LICENSE.txt"
