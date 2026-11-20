# Sourced by native-libraries with verified inputs and an owned staging tree.
# The bridge opts in for streaming uploads. Curl still validates and drains
# the response before reporting completion.
patch -f -F 0 -p1 -d "$source" < "$ROOT/scripts/c-libraries/libcurl-early-response.patch" >&2
architecture=''
case "$TARGET" in aarch64-apple-darwin) architecture=arm64 ;; x86_64-apple-darwin) architecture=x86_64 ;; esac
case "$SYSTEM" in
    darwin) zLibrary="$zlib/lib/libz.dylib"; sslLibrary="$openssl/lib/libssl.dylib"; cryptoLibrary="$openssl/lib/libcrypto.dylib" ;;
    linux) zLibrary="$zlib/lib/libz.so"; sslLibrary="$openssl/lib/libssl.so"; cryptoLibrary="$openssl/lib/libcrypto.so" ;;
    windows) zLibrary="$zlib/lib/libz.lib"; sslLibrary="$openssl/lib/libssl.lib"; cryptoLibrary="$openssl/lib/libcrypto.lib" ;;
esac
# LLVM MinGW links each DLL through its .dll.a import library.
if [ "$TARGET" = aarch64-pc-windows-gnullvm ]; then
    zLibrary="$zlib/lib/libz.dll.a"; sslLibrary="$openssl/lib/libssl.dll.a"; cryptoLibrary="$openssl/lib/libcrypto.dll.a"
fi
for dependency in "$zLibrary" "$sslLibrary" "$cryptoLibrary"; do
    [ -f "$dependency" ] || die "missing exact dependency library: $dependency"
done
apple_sectrust=
if [ "$SYSTEM" = darwin ]; then
    apple_sectrust=-DUSE_APPLE_SECTRUST=ON
fi
set --
case "$TARGET" in
    # The generator defaults to the OS architecture, even under vcvars64.
    x86_64-pc-windows-msvc) set -- -G "Visual Studio 17 2022" -A x64 ;;
    aarch64-pc-windows-gnullvm) set -- -G Ninja ;;
esac
cmake "$@" -S "$source" -B "$staged/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_INSTALL_PREFIX="$install" -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_INSTALL_NAME_DIR=@rpath \
    -DCMAKE_INSTALL_RPATH='@loader_path;$ORIGIN' -DBUILD_SHARED_LIBS=ON -DBUILD_STATIC_LIBS=OFF \
    -DBUILD_CURL_EXE=OFF -DBUILD_TESTING=OFF -DBUILD_LIBCURL_DOCS=OFF -DBUILD_MISC_DOCS=OFF \
    -DCURL_DISABLE_DICT=ON -DCURL_DISABLE_FILE=ON -DCURL_DISABLE_FTP=ON \
    -DCURL_DISABLE_GOPHER=ON -DCURL_DISABLE_IMAP=ON -DCURL_DISABLE_LDAP=ON -DCURL_DISABLE_IPFS=ON \
    -DCURL_DISABLE_LDAPS=ON -DCURL_DISABLE_MQTT=ON -DCURL_DISABLE_POP3=ON \
    -DCURL_DISABLE_RTSP=ON -DCURL_DISABLE_SMB=ON -DCURL_DISABLE_SMTP=ON \
    -DCURL_DISABLE_TELNET=ON -DCURL_DISABLE_TFTP=ON -DCURL_DISABLE_WEBSOCKETS=ON -DCURL_USE_OPENSSL=ON -DOPENSSL_ROOT_DIR="$openssl" -DZLIB_ROOT="$zlib" \
    ${apple_sectrust:+"$apple_sectrust"} \
    -DOPENSSL_INCLUDE_DIR="$openssl/include" -DOPENSSL_SSL_LIBRARY="$sslLibrary" -DOPENSSL_CRYPTO_LIBRARY="$cryptoLibrary" \
    -DZLIB_INCLUDE_DIR="$zlib/include" -DZLIB_LIBRARY="$zLibrary" \
    -DCURL_ZLIB=ON -DCURL_BROTLI=OFF -DCURL_ZSTD=OFF -DUSE_LIBIDN2=OFF -DCURL_USE_LIBPSL=OFF \
    -DUSE_NGHTTP2=OFF -DUSE_NGTCP2=OFF -DUSE_QUICHE=OFF -DUSE_MSH3=OFF \
    -DCURL_USE_LIBSSH2=OFF -DCURL_USE_LIBSSH=OFF -DCURL_USE_GSSAPI=OFF -DCURL_USE_PKGCONFIG=OFF \
    -DCURL_USE_LIBUV=OFF -DCURL_USE_RUSTLS=OFF -DCURL_USE_GNUTLS=OFF -DCURL_USE_MBEDTLS=OFF \
    -DCURL_USE_WOLFSSL=OFF -DCURL_USE_SCHANNEL=OFF -DCURL_USE_SECTRANSP=OFF >&2
cmake --build "$staged/build" --config Release --parallel "$JOBS" >&2
cmake --install "$staged/build" --config Release >&2
license="$source/COPYING"
