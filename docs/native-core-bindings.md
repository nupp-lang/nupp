# Standalone-core native bindings

The internal `nupp.runtime.core.compressioncodec` and `cryptocodec` modules use checked FFI directly against the pinned shared zlib and OpenSSL artifacts. They are independent of the existing frozen providers, which remain the default.

The listed core cases pass on macOS ARM64: the full transport/FFI/reactor/codec run passed 11,565 checks, including spill and forced collection. A follow-up sync-flush boundary run passed 1,273 checks in normal and spill modes. Receipts are under `docs/evidence/native-core-codecs`. These remain independent internal bindings; public facade integration and the complete runtime replacement have separate acceptance work.

The guest selectors are `compressioncodec` and `cryptocodec`. They need `NUPP_ZLIB_LIBRARY` and `NUPP_CRYPTO_LIBRARY` pointing at the exact provisioned shared libraries. The compression fixtures are checked-in binary vectors from an independent older zlib build, covering stored, fixed and dynamic blocks; no fixture generator runs in parallel guest jobs.

Core bindings, stream/facade integration, TLS/HTTP adapters, supported-target acceptance and coordinated Rust retirement are separate work. No existing provider selection, release artifact or published seed is changed here.

Sync flush needs an output window of at least seven bytes, as required by the pinned zlib header. Smaller nonempty windows fail before touching C and can be retried safely; ordinary stepping and finish still support one-byte windows.
