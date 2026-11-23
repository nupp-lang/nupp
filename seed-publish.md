# Publishing and pinning the next core seed

Recorded 2026-11-23 from the hostdecls lane's research. The owner approved
publishing this seed on 2026-11-22. No workflow exists for this: seeds .2, .3
and .4 were cut by hand, one tag per host.

## Order
1. The flip lands: the integration branch on core-dev, then macOS in
   `STAGE0_CORE_HOSTS`, then Linux and Windows ARM64.
2. Land `core-vm-sources` (4a145ffbf, "hostdecls"). Its commit invalidates every
   runtime kernel, so expect one cold build (about 3 h on a loaded machine).
3. Publish the seed from a core-dev commit that includes hostdecls (REV).
4. Pin it.
5. Delete `native/crates/vm/{lib,decls}` along with the crate. The old copies can
   go only when all of these have moved off them:
   - each core seed pin;
   - the VM execution seed in `scripts/bootstrap-seeds.json`, which builds
     fixpoint stage 1 and vm-cli on every unflipped host;
   - every worktree's installed core-cli builder built before hostdecls.

## Steps
1. Push REV to core-dev (`--target` needs it on the remote).
2. On each host (macOS ARM64 natively, Linux ARM64 in an arm64 container,
   Windows 11 ARM64 under MSYS2 clangarm64), from a clean checkout at REV:
   `NUPP_RUNTIME=core ./bin/nupp fixpoint --runtime core --package-seed "$PWD/build/core-seed"`
   This writes `nupp-core-seed-<host>-<REV>.tar.gz` and `.sha256`. Keep
   `build/core-fixpoint/receipt.json`.
3. Check each archive offline in a fresh environment:
   - `NUPP_HOST_OFFLINE=1 scripts/toolchain core-seed-install ARCHIVE SHA256`
   - then `scripts/core-self-build core RUNTIME COMPILER OUT`
   - On Linux, confirm that `ldd` resolves libcurl and libuv inside the seed.
4. Publish as a prerelease, never latest. The next free tag is
   `v0.0.15-core-seed.5`. That pattern is outside `vX.Y.Z`, so the release
   workflow doesn't fire.
   `gh release create v0.0.15-core-seed.5 <mac>.tar.gz <mac>.tar.gz.sha256 --target <full REV> --prerelease --latest=false --title ... --notes ...`
   then `gh release upload` the Linux and Windows archives and their `.sha256`
   files. One tag per host is also acceptable, as before.
5. Pin in `scripts/toolchain.pins`:
   - set `STAGE0_CORE_URL_*` and `STAGE0_CORE_SHA256_*` for
     `AARCH64_APPLE_DARWIN`, `AARCH64_UNKNOWN_LINUX_GNU` and
     `AARCH64_PC_WINDOWS_GNULLVM`;
   - update the comment naming the tags.
6. Before committing the pin, on each host, with a fresh cache:
   - `rm -rf .nupp-cache/toolchain/core-seed/*`
   - `seed=$(sh scripts/toolchain core-seed)`
   - `sh scripts/core-self-build core "$seed/runtime" "$seed/compiler.bundle" build/seed-check`
   - run the core fixpoint.

   To rehearse before publishing, set `NUPP_HOST_SOURCE_DIR` to a directory
   holding the archives.
7. Commit: "Pin the ARM64 core seeds v0.0.15-core-seed.5".

## Notes
- Today the pinned core seeds only anchor the core-cli builder. Fixpoint stage 1
  uses the VM seed on every host, and that changes with the flip.
- `scripts/core-cli` SOURCES never listed the crate's decls. Under `src/` they
  are now covered.
