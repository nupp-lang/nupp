# Sourced by the Linux core HTTP build. ROOT and die come from the caller.
# pkg-config selects the host's ICU development package. The runtime uses
# the corresponding system ICU libraries and data.
icu_include=$(pkg-config --variable=includedir icu-uc) ||
    die 'cannot find ICU headers: install pkg-config and the ICU development package'
icu_libdir=$(pkg-config --variable=libdir icu-uc) ||
    die 'cannot find the ICU library directory'

case "$icu_include" in
    /*) ;;
    *) die 'ICU include directory must be absolute' ;;
esac
case "$icu_libdir" in
    /*) ;;
    *) die 'ICU library directory must be absolute' ;;
esac
icu="$icu_libdir/libicuuc.so"
[ -r "$icu_include/unicode/uidna.h" ] && [ -r "$icu" ] ||
    die 'selected ICU SDK lacks unicode/uidna.h or libicuuc.so'

curl=$(sh "$ROOT/scripts/native-libraries" libcurl) ||
    die 'could not provision pinned libcurl'
[ -r "$curl/include/curl/curl.h" ] && [ -r "$curl/lib/libcurl.so" ] ||
    die 'pinned libcurl SDK lacks curl/curl.h or libcurl.so'
