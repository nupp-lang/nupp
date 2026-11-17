# Sync-flush boundary regression

On November 16, 2026, the checked source identities in `receipt.json` passed **1,273 checks, zero failures, 688 seconds** on the actual macOS ARM64 core through the C startup transport. The case ran in both normal and spill modes with ABI/scratch guards and failure audits. Forced collection was not repeated for this focused argument-boundary change; the earlier full receipt records that coverage.

```sh
NUPP_VM_AUTO_REBUILD=0 NUPP_GUEST_JOBS=4 NUPP_GUEST_SHARDS=1 \
NUPP_GUEST_STRESS=0 NUPP_CORE_TRANSPORT=c \
NUPP_ZLIB_LIBRARY="$(./scripts/toolchain zlib)/lib/libz.dylib" \
./bin/nupp run tests/core/guests/run.lua compressioncodec
```

The pinned zlib header requires more than six output bytes when a sync-flush marker begins; otherwise repeated full tiny windows can keep generating empty markers. The binding now rejects nonempty windows smaller than seven before entering C. The new real-core test catches that refusal, retries on the same state with seven bytes, reaches a completed flush in a bounded loop and then finishes the stream. Existing empty/level/block-kind/one-byte/truncation/corruption cases also ran. No-flush and finish keep one-byte output support.
