# Changelog

## Unreleased

- Say when a closure that reads its iteration costs a loop its trace. The new
  `jit-loop-closure` lint (`NUPP2515`) is off until a project asks for it,
  since the code it reports is correct and has no mechanical fix, but a
  function annotated `@jit` promised that it compiles and reports the same
  hazard as `NUPP2707` whatever level the lint is at.
- Say what a build is doing while it runs, and where its wall-clock time went
  and which modules cost the most when it ends. Reported to a terminal only;
  `--progress`, `-q` and `NUPP_PROGRESS` say otherwise, and `build --json`
  carries the same numbers in a `timing` object.
- Type `ffi.C` from a C function this process had already declared, which an
  ordering accident between the compiler's own code and the file it is
  checking could previously empty.
- Add deterministic target-aware C header export and typed ordinary-struct
  pointer interoperation through `nupp export-c`.
- Add explicit allocation-free `nupp.math.i32`, `u32`, and IEEE-754 binary32
  scalar operations.
- Add affine writable span slices, allocation-free checked common ranges, and
  ownership-qualified typed variadic parameters.
- Add `noalloc do` and `noraise do` regions with observed cross-module
  guarantees and cleanup-aware effect inference.
- Increase the single isolated comptime-worker deadline to 10 seconds so
  bounded evaluation includes compiler startup under parallel build load.
