# Native core codec and transport proof

On November 16, 2026, public Nupp commit `39410809e286a2f86a0d12a8469f9411eacd54a7` passed **11,565 checks, zero failures, 999 seconds** on macOS ARM64. `receipt.json` binds the source, fixture, compiler image and matching runtime identities. This is actual standalone-core execution through the C startup transport, not the frozen Rust provider or a substitute codec.

```sh
NUPP_VM_AUTO_REBUILD=0 NUPP_GUEST_JOBS=4 NUPP_GUEST_SHARDS=1 \
NUPP_CORE_TRANSPORT=c \
NUPP_ZLIB_LIBRARY="$(./scripts/toolchain zlib)/lib/libz.dylib" \
NUPP_CRYPTO_LIBRARY="$(./scripts/toolchain openssl)/lib/libcrypto.dylib" \
./bin/nupp run tests/core/guests/run.lua \
  cbridge guestffi ffiaggregates tasksreactor reactorfiles reactorpipes \
  nullablepointers compressioncodec cryptocodec
```

All nine selections ran in normal and spill modes, with ABI/scratch guards, collect-at-every-allocation and interleaved collection, cancellation/budget controls and the runner's malformed-artifact audits. The 18 programs were selected in 384 seconds. Most remaining time was the compression case with forced collection and spill. These times describe validation, not a throughput benchmark.

The pointer regression distinguishes null and non-null C fields from an ordinary zero-valued uint64 field, including parameter-valued assignments. Compression checks gzip, zlib and raw DEFLATE; empty streams, levels 0 and 9; all three legal block kinds; one-byte input/output; truncation and corrupted wrapper trailers. Independent fixtures are checked in; the provider does not generate its own oracle. Crypto checks split and empty SHA-256, split HMAC-SHA-256, empty-key/empty-message HMAC, copied key/input lifetimes while contexts are held in lexical cleanup scopes.

Initial execution exposed pointer signature admission, null-field conversion, mutable branch-selection transport, unsupported carray construction and treating zlib Z_STREAM_END as an error. The tested revision corrects them. The OpenSSL parameter list uses two contiguous checked nested C structs, including the zero terminator; no C SDK wrapper is added.

The five-platform upstream C artifact proof is separate, under `docs/evidence/native-c-dependencies`. This receipt accepts only the listed core cases on macOS ARM64. It does not claim other core target adapters, rooted stream/facade integration, TLS/HTTP adapters, the future complete inventory runner, callback lifetime acceptance, Rust retirement, or a Rust-free compiler bootstrap. The frozen providers remain the defaults.
