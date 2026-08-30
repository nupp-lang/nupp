# Nupp TODO

A living list, not a design record. Items are removed when completed.

## Transport security

- [ ] **A platform trust store.** `tls.ClientOptions.authority` is PEM the
      caller supplies, so verifying against the public web PKI needs roots from
      somewhere. Three designs, and they fail differently: extract the
      platform's roots and verify with mbedTLS, delegate verification to the
      platform (Security.framework, CryptoAPI), or ship a bundled list. Linux
      has no API and the file location varies by distribution.
## GPU compute

- [ ] **Decide the GPU test-device policy.** NEP 25 requires it before
      Accepted: either a pinned software Vulkan implementation becomes the
      conformance device on headless runners, or the exclusion is named and
      deliberate. Everything below lands suites behind this decision.
- [ ] **Emit SPIR-V and derive MSL.** The largest single work item: a binary
      SPIR-V emitter with structured control flow from the verified IR, plus a
      pinned SPIRV-Cross build. On Metal, "precompiled" still means MSL source
      compiled at pipeline creation unless the Apple toolchain exception is
      taken; name whichever is chosen.
- [ ] **Extend the partial-guard admission to the CPU AOT tier.** The GPU map
      admits a guard covering only dispatch-indexed spans, with cursor-proved
      spans free; the CPU map still demands full coverage, so a GEMM body
      compiles for GPU and is refused for CPU. `bench/sdl-gpu-spike/typed/
      gemm.nupp` is the reproduction.
- [ ] **Make the kernel loop index a value.** `u32.wrap(i)` and arithmetic on
      it are refused inside kernels, which is why the GEMM benchmark ships
      precomputed row/column index spans. Integer division intrinsics
      (`u32.div`, `u32.mod`) fall out of the same design pass.
- [ ] **Propose structured workgroup phases.** Its own NEP: statically sized
      workgroup scratch, stages whose boundaries are the barriers, writes
      structurally disjoint by `shared[localIndex]`, CPU meaning = stages run
      to completion in order. Validated by a tiled f32 GEMM against the naive
      baseline in `bench/sdl-gpu-spike`.
- [ ] **Map `f32.fma` and f16 storage into the GPU subset.** `f32_fma` exists
      in the IR and is correctly rounded, so it is bit-identical for free; the
      emitter does not map it yet. FP16 storage with f32 accumulation follows.
- [ ] **Define polynomial transcendentals before softmax.** No GPU or libm
      promises correctly rounded f32 `exp`, so softmax breaks bit-identity
      before tensor cores do. An IR-defined polynomial over mul/add/fma is the
      same instruction sequence on both sides and stays exact by construction.
- [ ] **Fixed-tree reductions over the declared workgroup size.** The CPU
      implementation performs the same tree, so both sides share one specified
      order. No unordered/fast reduction family: a backend-chosen order has no
      CPU definition and would end the ordinary-semantics invariant.
- [ ] **Tensor views and chained kernels, then a tiny transformer.** Shape and
      stride validation over resident buffers, subviews without allocation, no
      broadcasting. Cooperative-matrix variants come last, behind a tolerance
      NEP, because hardware accumulation order cannot match one CPU
      definition.
