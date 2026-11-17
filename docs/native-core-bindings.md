# Standalone-core native bindings

The internal `nupp.runtime.core.compressioncodec` and `cryptocodec` modules use checked FFI directly against the pinned shared zlib and OpenSSL artifacts. They are independent of the existing frozen providers, which remain the default.

These bindings are under active validation and are not accepted replacements yet. Initial real-core checks exposed nullable C pointer field conversion, parameter-valued branch selection, and an unsupported `carray` construction in the crypto binding. Corrections and a dedicated `nullablepointers` core regression are included. The pointer, compression and crypto cases pass in normal mode on macOS ARM64; spill, collection-stress and complete failure audits remain in progress. Shared compiler/facade tests are not evidence that these core providers execute successfully.

The guest selectors are `compressioncodec` and `cryptocodec`. They need `NUPP_ZLIB_LIBRARY` and `NUPP_CRYPTO_LIBRARY` pointing at the exact provisioned shared libraries. The compression fixtures are checked-in binary vectors from an independent older zlib build, covering stored, fixed and dynamic blocks; no fixture generator runs in parallel guest jobs.

Core bindings, stream/facade integration, TLS/HTTP adapters, supported-target acceptance and coordinated Rust retirement are separate work. No existing provider selection, release artifact or published seed is changed here.
