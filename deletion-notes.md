# VM deletion notes (inventory at 2ea96ec7c, 2026-11-22)

Key constraints found:
- native/crates/vm/{lib,decls} hold 38 Nupp/.d.nupp/.lua files read by shared code
  (compiler/project/env.nupp:2750 vmDeclarations, compiler/bundled.nupp:123, compiler/runtime/init.nupp:114-138,
  core/kernelcompiler.nupp:45-54, core/produceridentity.nupp:25, tools/build/package.nupp:190,
  compiler/vm/legacylower.nupp:4208, nupp.lua:542 RESOURCES). Pinned core seeds may open these by path:
  keep them in place (or duplicated) until a seed from a commit reading the new location is pinned.
- On a flipped host the VM is still reached by scripts/test-changed:34-35 (bootstrap-seed run ... nupp.tools.vm.root),
  `__native-core` (cli/init.nupp:184), tests calling scripts/vm-cli / NUPP_RUNTIME=vm, CI GPU and seed jobs.
- GPU provider (runtime/provider/{wgpu,wgpumemory,gpucosts}.nupp, src/nupp/foreign.nupp) requires nupp.vm.foreign,
  which has no core mapping (compiler/vm/graphcalls.nupp coremodules). Rewire to nupp.runtime.foreigncalls.
- core bundle carries clif.lower/ssa/legacygraph via cli/fixpoint -> tools.vm.packaging -> buildsteps.
- core/guestbuild.nupp:80-90 parses ROOT_EXTRAS from src/nupp/tools/vm/project.nupp text.
- piecestore/selectioncache/fingerprint/produceridentity key on NUPP_VM_CLI_IMAGE / .nupp/vm-cli.
