# Nupp AOT TODO

## Specialization

- [ ] **10. Add AOT const monomorphization.** Conditional on 8 or 9 showing a
      meaningful fixed-constant advantage. The target-tier machinery already
      supplies multiple emitted bodies, physical symbol naming, separate
      translation units, boundary dispatch and code-size accounting, and should
      be reused rather than rebuilt.

      It supplies the artifact machinery and not the semantic key. A tier is a
      fixed set the build enumerates; a const tuple is an open set discovered
      from source, so it needs its own specialization key and its own
      incremental dependency identity. Body count per module needs a cap and a
      diagnostic naming the call sites that reached it, and
      `timing.compiledModules` stops being a clean proxy for work once one
      module emits several bodies.

      What makes this compatible with
      [NEP 3](docs/neps/0003-comptime.md)'s exclusions is that it duplicates
      emission and never meaning: the signature and body stay written in
      source, so a tool still describes them without executing anything. That
      is why the NEP defers it rather than excluding it

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
