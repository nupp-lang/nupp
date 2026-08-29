# Nupp AOT TODO

## Specialization

- [ ] **11. Prototype deterministic tuning.** Conditional on several
      monomorphic shapes having meaningfully different winners *across targets
      that are actually shipped to*. If one shape wins everywhere, the answer
      is a committed constant and no tuning artifact is needed; if winners vary
      by target, a single committed artifact is wrong and the file needs
      per-target entries with a selection rule. Settle that before
      prototyping, because it decides the artifact's shape rather than its
      contents.

      Use a reviewed, committed tuning artifact first: a bench step sweeps and
      writes it, a person reviews and commits it, and compilation only ever
      reads committed bytes, so `fixpoint` still holds. Extend
      `nupp.derive.file`-style access to comptime only if that workflow proves
      too awkward, and reject the extension if its invalidation fan-out is
      excessive -- a comptime block reading a file is a dependency edge from
      every module that transitively uses the result, which is wider than one
      provider's
