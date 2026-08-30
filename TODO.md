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

- [ ] **Propose structured workgroup phases.** Its own NEP: statically sized
      workgroup scratch, stages whose boundaries are the barriers, writes
      structurally disjoint by `shared[localIndex]`, CPU meaning = stages run
      to completion in order. Validated by a tiled f32 GEMM against the naive
      baseline in `bench/sdl-gpu-spike`.
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
