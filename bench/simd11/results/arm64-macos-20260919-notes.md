# Interpreting the complete-function comparisons

The [qualified measurements](arm64-macos-20260919-3.md) compare native SIMD with
an optimized scalar-source artifact whose automatic vectorization is disabled.
Both paths come from the same compiler revision. Nine independent processes
and the frozen 1% duration margin establish the reported verdicts. All sixteen
cases pass the independent correctness checks and original scalar-C oracle.

Refinement takes 1.245× the control duration at 63 elements and 1.134× at
65,539. Its four-lane native loop maintains live masks and preserves retired
values and counters with selects. The measured assembly has 21 instructions
per vector round, including four selects and a mask reduction followed by a
scalar branch; the scalar control has a five-instruction per-element round.
For these inputs, arithmetic on inactive lanes is only about 2.3% and 4.5%,
respectively. Mask maintenance, reduction, setup and tails are concrete extra
work; divergence alone does not explain the entire measured difference.

Cross-lane processing takes 1.876× and 2.119× the control duration. The authored
function composes reverse, ordered prefix sum and compress. Native prefix work
extracts scalar lanes, and dynamic compress insertions repeatedly spill and
reload the vector. Its stack frame is 144 bytes. The scalar control uses scalar
sums and conditional stores into a 16-byte scratch area, with a 16-byte frame.
The native path consequently moves values between vector registers, scalar
registers and the stack instead of using a packed NEON compress operation.

ASCII UTF-8 at 63 bytes takes 1.070× the control duration. Native code eagerly
initializes four vector constants and non-ASCII table machinery, then reduces
the high-bit mask for each group. The scalar control tests two 64-bit words
with integer masks. There are only three full groups before both paths rewind
three bytes and scalar-decode the final eighteen bytes. These are plausible
contributors to the short-input cost; this inspection does not measure their
individual contributions. At 65,539 ASCII bytes the native path is faster.

The inspected C and assembly hashes match the [raw measurement record](arm64-macos-20260919-3.json).
After integration, `fdc424a5` reproduces all twelve source, assembly and binary
hashes exactly and passes all sixteen correctness cases again; the
[identity check](arm64-macos-artifact-equivalence.json) preserves both revision
identities.
Original artifacts are retained at
`/private/tmp/nupp-simd11-measured-artifacts-9d7b176e`. Relevant locations within
that frozen directory are `native.c:2032`, `native.s:325`, `no_vector.s:244`
for refinement; `native.c:2247`, `native.s:2040`, `no_vector.s:1422` for the
cross-lane function; and `utf8/native.s:2198`, `utf8/no_vector.s:119`,
`utf8/native.c:1499` for UTF-8. The measurement harness regenerates these
artifacts and checks native arithmetic and the separate no-vector control.
