#!/bin/sh
# Fetches the pinned Terra release this benchmark measures against.
#
# Terra is nothing else in this repository's business: no part of Nupp builds
# against it and no test needs it, so it is not a `scripts/toolchain`
# component. It is fetched here, verified against the digest the release
# publishes, and unpacked into `vendor/`, which is ignored. A fresh checkout has
# none and `run.sh` calls this before it needs one.
#
# The pin is a release rather than a range. A benchmark whose control moves on
# its own reports a difference between two machines as a difference between two
# languages.
set -eu

cd "$(dirname "$0")"

RELEASE=release-1.2.2
BUILD=bb02b25

case "$(uname -s)-$(uname -m)" in
    Darwin-arm64)
        PLATFORM=OSX-aarch64
        DIGEST=6942918f12c24b55ddc861ddeb4e3c399856b6f5c5813fd7ec7a069b97881976
        ;;
    Darwin-x86_64)
        PLATFORM=OSX-x86_64
        DIGEST=0e2eaef0b04bda300b0fcd2435efa1ca0b8de4cbbd62eff4487b7d7d99cb1fe8
        ;;
    Linux-aarch64 | Linux-arm64)
        PLATFORM=Linux-aarch64
        DIGEST=79e3a33a2f6f1c334128f8623751ff4224cc72e82a0f8f61cea96e8cda119c65
        ;;
    Linux-x86_64)
        PLATFORM=Linux-x86_64
        DIGEST=7359c60f056a0300c1f3cbc11c26f370b62f6b8216190a78739b362ccf432593
        ;;
    *)
        echo "terra: no pinned release for $(uname -s)-$(uname -m)" >&2
        echo "terra: add its name and digest from the $RELEASE assets" >&2
        exit 1
        ;;
esac

PREFIX="vendor/terra-$PLATFORM-$BUILD"
if [ -x "$PREFIX/bin/terra" ]; then
    echo "$PREFIX"
    exit 0
fi

ARCHIVE="terra-$PLATFORM-$BUILD.tar.xz"
URL="https://github.com/terralang/terra/releases/download/$RELEASE/$ARCHIVE"

mkdir -p vendor
echo "terra: fetching $ARCHIVE" >&2
curl -fsSL -o "vendor/$ARCHIVE" "$URL"

if command -v shasum >/dev/null 2>&1; then
    ACTUAL=$(shasum -a 256 "vendor/$ARCHIVE" | cut -d' ' -f1)
else
    ACTUAL=$(sha256sum "vendor/$ARCHIVE" | cut -d' ' -f1)
fi

if [ "$ACTUAL" != "$DIGEST" ]; then
    rm -f "vendor/$ARCHIVE"
    echo "terra: $ARCHIVE does not match its pinned digest" >&2
    echo "terra:   expected $DIGEST" >&2
    echo "terra:   actual   $ACTUAL" >&2
    exit 1
fi

tar -xf "vendor/$ARCHIVE" -C vendor
rm -f "vendor/$ARCHIVE"
echo "$PREFIX"
