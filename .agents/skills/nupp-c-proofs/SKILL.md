---
name: nupp-c-proofs
description: Add, update, or diagnose CBMC proofs for Nupp-owned C. Use when a C contract needs a bounded proof or an existing proof fails.
---

# Nupp C proofs

Start with a specific property of production C, such as copy bounds, size
arithmetic, or a state invariant. Use the [Nupp C style](../nupp-c-style/SKILL.md)
for code and Doxygen comments.

- Put the harness in `tests/core/<name>proof.c` and include
  [proofintrinsics.h](../../../tests/core/proofintrinsics.h) for symbolic inputs.
  Exercise the production implementation. A small private header works for
  shared C helpers that can run independently of the host or a native library.
- Model inputs symbolically. Use assumptions for caller contracts and explain
  where production establishes them. State the exact capacity, sequence length,
  or input domain when the proof uses a smaller model. Check full-width
  arithmetic separately when a symbolic loop or heap would make it expensive.
- Write assertions against the contract or an independent calculation. Check
  that both ordinary success and relevant failure paths are reachable. Verify
  that an intentional local defect fails the expected assertion, then restore
  the production code.

Register a stable task argument, harness filename, and unwind bound in
[proofs.nupp](../../../tests/core/proofs.nupp). Allow for the loop's final exit
check and keep the task's unwinding assertions enabled. Add any new production C
sources and headers the proof depends on to its CI selection in
[classify-changes.lua](../../../.github/scripts/classify-changes.lua).
Register the task name in that selector and add its harness to the same group.
The shared `proofintrinsics.h` selects every proof.

Run `./bin/nupp task proofs NAME` while iterating, then `./bin/nupp task proofs`.
Set `CBMC` to the executable path to match the version pinned in the
[compiler workflow](../../../.github/workflows/compiler.yml). Report the claim,
assumptions, and bounds alongside the result.
