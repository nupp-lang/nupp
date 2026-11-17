# Pinned C dependency conformance

All five native artifact jobs passed at `9adc26897362a419bebc83d01ffd385bbd9bcec7` in [run 43990338674](https://github.com/nupp-lang/nupp/actions/runs/43990338674). These receipts contain only target, version, ABI, timing and artifact digests.

Each job built the pinned shared zlib 1.4, OpenSSL 3.5.9 and curl 8.23.0 from verified sources with Rust tools replaced by fail-fast commands. The C probe checked compression roundtrips and corruption, SHA-256 and HMAC vectors, an SSL context, linked dependency versions, and the HTTP/HTTPS-only curl feature set. The seven cache/refusal/concurrent-publication tests ran too (the symlink test skips where Windows cannot create file symlinks).

`timing.json` distinguishes initial provisioning from verified warm reuse, which rebuilt nothing. Times describe hosted runners and their cache state, not compiler build speed. The identities bind target, source, toolchain, dependencies and installed file manifest.

These are upstream C artifact proofs. They do not accept a Nupp TLS/HTTP provider, the new standalone-core codecs, or retirement of the existing Rust providers. OpenSSL is the pinned 3.5.9 release; no claim is made about fixes in unreleased versions.
