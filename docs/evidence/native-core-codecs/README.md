# Standalone-core native binding receipts

- [Full transport, pointer, codec and reactor matrix](full-39410809e/README.md): 11,565 checks passed, including forced collection and spill.
- [Sync-flush boundary regression](sync-flush/README.md): 1,273 checks passed in normal and spill modes, including refusal and valid retry.
- [Compiler fixpoint](fixpoint.json): three pinned-seed stages emit byte-identical compiler images.

Only macOS ARM64 core execution is accepted by these receipts. Five-platform C dependency artifacts have a separate proof in `docs/evidence/native-c-dependencies`. No public provider switch, other core target acceptance, TLS/HTTP adapter, Rust retirement or release publication is implied.
