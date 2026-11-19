# Source only for the opt-in x64 MSVC HTTP fixture. ROOT and die come from
# the caller. The combined icu.dll requires Windows 10 1903 or Server 2022.
# Build uriidna.c with -DNUPP_WIN64_HTTP_SYSTEM_ICU=1 and icu_include;
# link icu_import. Use the system DLL and stage only curl_dlls beside the
# executable, with curl_notices from the same verified curl package.
[ -n "${WindowsSdkDir:-}" ] && [ -n "${WindowsSDKVersion:-}" ] ||
    die 'Win64 HTTP requires the selected x64 Windows SDK environment'
windows_sdk=$(cygpath -u "$WindowsSdkDir") || die 'invalid Windows SDK path'
windows_sdk_version=${WindowsSDKVersion%\\}
windows_sdk_version=${windows_sdk_version%/}
icu_include="$windows_sdk/Include/$windows_sdk_version/um"
icu_import="$windows_sdk/Lib/$windows_sdk_version/um/x64/icu.lib"
[ -s "$icu_include/icu.h" ] && [ -s "$icu_import" ] ||
    die 'selected x64 Windows SDK lacks icu.h or icu.lib'

curl=$(NUPP_NATIVE_TARGET=x86_64-pc-windows-msvc NUPP_CC=cl sh "$ROOT/scripts/native-libraries" libcurl) ||
    die 'could not provision pinned MSVC libcurl'
curl_import="$curl/lib/libcurl_imp.lib"
curl_dlls='libcurl.dll libssl-3-x64.dll libcrypto-3-x64.dll libz.dll'
curl_notices='libcurl-LICENSE.txt OpenSSL-LICENSE.txt zlib-LICENSE.txt'

[ -s "$curl/include/curl/curl.h" ] && [ -s "$curl_import" ] ||
    die 'pinned MSVC libcurl SDK lacks its header or import library'
for dll in $curl_dlls; do
    [ -s "$curl/bin/$dll" ] || die "pinned MSVC libcurl SDK lacks $dll"
done
for notice in $curl_notices; do
    [ -s "$curl/notices/$notice" ] || die "pinned MSVC libcurl SDK lacks $notice"
done
