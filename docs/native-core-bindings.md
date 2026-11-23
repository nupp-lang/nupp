# Standalone-core native bindings

The internal `nupp.runtime.core.compressioncodec`, `crccodec` and `cryptocodec` modules use checked FFI directly against the pinned shared zlib, ISA-L CRC and OpenSSL artifacts. The compression and CRC codecs are also what the VM's compression provider and checksum catalog call, so one binding serves both runtimes; the Rust compression and checksum crates are gone. The compression codec selects zlib's LP64 or Windows LLP64 stream layout from the loaded library's compile flags. The compiler binds the logical `nuppzlib` and `nuppcrc` libraries to `NUPP_ZLIB_LIBRARY` and `NUPP_CRC_LIBRARY` unless a project configures them; when neither variable is set, a source checkout's compiler builds them through `scripts/c-library-paths` the first time a program binds one.

The listed core cases pass on macOS ARM64: the full transport/FFI/reactor/codec run passed 11,565 checks, including spill and forced collection. A follow-up sync-flush boundary run passed 1,273 checks in normal and spill modes. Receipts are under `docs/evidence/native-core-codecs`. These remain independent internal bindings; public facade integration and the complete runtime replacement have separate acceptance work.

The guest selectors are `compressioncodec` and `cryptocodec`. They need `NUPP_ZLIB_LIBRARY` and `NUPP_CRYPTO_LIBRARY` pointing at the exact provisioned shared libraries. The compression fixtures are checked-in binary vectors from an independent older zlib build, covering stored, fixed and dynamic blocks; no fixture generator runs in parallel guest jobs.

Core bindings, stream/facade integration, TLS/HTTP adapters, supported-target acceptance and coordinated Rust retirement are separate work. No existing provider selection, release artifact or published seed is changed here.

Sync flush needs an output window of at least seven bytes, as required by the pinned zlib header. Smaller nonempty windows fail before touching C and can be retried safely; ordinary stepping and finish still support one-byte windows.

`nupp.runtime.core.yamlcodec` binds the pinned libyaml (`nuppyaml`, built as `nupp_yaml` by `scripts/c-libraries/libyaml.sh`) the same way, for `serde.yaml`. libyaml's parser, emitter and event structures are read through overlays whose sizes and offsets `scripts/c-libraries/libyamlprobe.c` holds every target to, since the core's FFI passes no union. The emitter writes only through a callback, so its handler is the C bridge's byte sink, `nuppappendbytes`, and the bytes are read once the emitter has flushed.
