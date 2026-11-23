# Sourced by native-libraries with verified inputs and an owned staging tree.
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
set --
case "$TARGET" in
    x86_64-pc-windows-msvc) set -- -G "Visual Studio 17 2022" -A x64 ;;
    aarch64-pc-windows-gnullvm) set -- -G Ninja ;;
esac
cmake -S "$ROOT/native/sqlite" -B "$staged/build" \
    "$@" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DCMAKE_INSTALL_PREFIX="$install" -DSQLITE_SOURCE="$source" >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
# SQLite is in the public domain. Its notice is the blessing the amalgamation
# opens with, which native-libraries compares with notices/.
license="$staged/sqlite-PUBLIC-DOMAIN.txt"
awk '/The author disclaims copyright to this source code/ { found = 1 }
    found { print }
    found && /never taking more than you give/ { exit }' "$source/sqlite3.c" > "$license"
