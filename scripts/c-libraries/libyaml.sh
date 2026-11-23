# Sourced by native-libraries with verified inputs and an owned staging tree.
# Builds the pinned libyaml as nupp_yaml (native/yaml), then refuses an
# artifact whose layouts differ from the ones serde.yaml's binding reads
# (libyamlprobe.c) before it is published.
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
set --
if [ "$SYSTEM" = windows ]; then set -- -G Ninja; fi
cmake "$@" -S "$ROOT/native/yaml" -B "$staged/build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_INSTALL_NAME_DIR=@rpath -DCMAKE_INSTALL_PREFIX="$install" \
    -DLIBYAML_SOURCE="$source" -DLIBYAML_VERSION="$version" >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
probe="$ROOT/scripts/c-libraries/libyamlprobe.c"
set -- ${CPPFLAGS:-} ${CFLAGS:-} -UNDEBUG -std=c11 -Wall -Wextra -Werror -I"$install/include"
case "$SYSTEM" in
    windows)
        [ -f "$install/bin/nupp_yaml.dll" ] || die 'libyaml installed no nupp_yaml.dll'
        "$CC" "$@" "$probe" "$install/lib/nupp_yaml.dll.a" -o "$staged/libyaml-layout.exe" >&2
        cp "$install/bin/nupp_yaml.dll" "$staged/nupp_yaml.dll"
        "$staged/libyaml-layout.exe" >&2
        ;;
    darwin)
        "$CC" "$@" "$probe" "$install/lib/libnupp_yaml.dylib" -Wl,-rpath,"$install/lib" -o "$staged/libyaml-layout" >&2
        "$staged/libyaml-layout" >&2
        ;;
    *)
        "$CC" "$@" "$probe" "$install/lib/libnupp_yaml.so" -Wl,-rpath,"$install/lib" -o "$staged/libyaml-layout" >&2
        "$staged/libyaml-layout" >&2
        ;;
esac
license="$source/License"
