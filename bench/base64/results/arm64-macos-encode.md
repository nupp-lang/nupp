# Base64 encode, arm64 macOS

## What stands

This document is chronological and several of its middle sections were
withdrawn by later ones. The findings that survived, and the numbers as they
are now measured:

| bytes | shipped | aot | const | nupp-simd | cv-warm | cv-fresh | memcpy |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1,024 | 14.535 | 1.135 | 0.742 | 0.470 | 0.418 | 0.515 | 0.385 |
| 65,536 | 13.650 | 0.738 | 0.352 | 0.076 | 0.075 | 0.088 | 0.016 |
| 1,048,576 | 15.059 | 0.730 | 0.353 | 0.073 | 0.072 | 0.172 | 0.013 |

`shipped` is `nupp.runtime.browser.base64`'s encoder, which is the only base64
Nupp has. It is here to say what the distance actually is: about 200x at a
megabyte, and 21x of that before any vector operation is reached. Note that
nothing can substitute one for the other today -- the shipped encoder runs in
the browser runtime, where the compiled entry does not exist.

- **The vectorized entry matches hand-written C**, to three decimal places
  against a warm control at both sizes, once both build the Lua string.
- **Allocation, not encoding, dominated at a megabyte** -- 61 percent -- until
  the buffer was reused rather than allocated per call.
- **The bounds guards are not the cost.** Ablating them moves the encode by
  about 8 points, not the multiple it looked like.
- **A benchmark that discards results excuses a C control from work an AOT
  entry cannot avoid.** LuaJIT eliminated the control's `ffi.string`; the
  harness now reads each result.
- **Nothing here encodes at close to the speed of a copy.** The entry is about
  six times memcpy at a megabyte.

Everything below is the order it was found in. Where a section was withdrawn,
the section that withdrew it says so.


`./run.sh` on Darwin 25.6.0, Apple silicon, LuaJIT, clang `-O2`. Nanoseconds
per input byte; lower is better.

- **aot** reads one byte at a time and writes one byte at a time.
- **words** reads three aligned `uint32` per twelve input bytes and writes one
  byte at a time.
- **words-nostore** is that entry with its stores removed: same reads, same
  arithmetic, same alphabet lookups, digits folded instead of written.

| bytes | aot | words | words-nostore | c-scalar | c-vector |
| --- | --- | --- | --- | --- | --- |
| 64 | 6.941 | 6.693 | 6.241 | 5.663 | 5.496 |
| 1,024 | 1.216 | 0.969 | 0.674 | 0.592 | 0.390 |
| 65,536 | 0.888 | 0.673 | 0.320 | 0.260 | 0.050 |
| 1,048,576 | 0.946 | 0.668 | 0.317 | 0.251 | 0.044 |

Runs agreed within noise at and above 1 KiB. The 64-byte row is call overhead
in every column and settles nothing.

## What the columns say

**Word reads were worth 1.42x and cost no compiler change.** 0.946 to 0.668 at
1 MiB. Twelve input bytes are three aligned words and four twenty-four bit
groups, so an iteration pays three checked reads where the byte-at-a-time entry
paid twelve. `valuebuilder.word` already existed and `nupp.data.digest` already
used it.

**The read side is now nearly closed.** words-nostore is 0.317 against scalar
C's 0.251, or 1.26x. Before word reads the same comparison was 1.53x. Whatever
is left there is small.

**The output path is now the whole remaining scalar gap.** 0.668 against 0.317
is 2.11x: over half of the entry is `setScratchByte`, one call per output byte.
Nothing else in the entry is close to that.

**The vectorized ceiling is 5.7x scalar C.** NEON reaches 0.044 ns per byte.
That is the literature's result reproduced and the honest ceiling for this
algorithm on this machine.

## Where that leaves the 22x

The byte-at-a-time entry was 21.5x off the vectorized ceiling. The
word-reading one is 15.2x, and it decomposes cleanly:

| factor | measured | what it is |
| --- | --- | --- |
| 2.11x | 0.668 → 0.317 | the byte-at-a-time output path |
| 1.26x | 0.317 → 0.251 | what remains of reads and arithmetic |
| 5.70x | 0.251 → 0.044 | vectorization |

Only the last of those needs an operation that knows what a vector is.

## Step one: a word-wide store

`valuebuilder.setScratchBytes4` writes four bytes at a byte index from one
`uint32`, least significant first. One operation, plain scalar C in the
emitter -- one guarded unaligned store -- with no feature tier and no
per-architecture fallback. The **stores** column is the word-reading encoder
using it: four stores per twelve input bytes where **words** does sixteen.

| bytes | aot | words | stores | w-nostore | c-scalar | c-vector |
| --- | --- | --- | --- | --- | --- | --- |
| 64 | 6.192 | 6.069 | 6.047 | 5.709 | 5.035 | 4.899 |
| 1,024 | 1.131 | 0.899 | 0.786 | 0.620 | 0.541 | 0.348 |
| 65,536 | 0.830 | 0.581 | 0.468 | 0.289 | 0.242 | 0.045 |
| 1,048,576 | 0.880 | 0.603 | 0.493 | 0.286 | 0.237 | 0.040 |

**It was worth 1.22x, and it missed its gate.** The gate was the entry within
1.5x of scalar C at 64 KiB. It reached 1.93x -- 0.468 against 0.242. Cumulative
against the original byte-at-a-time entry the two steps are 1.79x, and the
distance to the vectorized ceiling is 12.4x where it started at 21.5x.

**Why it is short of the ablation.** w-nostore says the output path was worth
2.09x, and only 1.22x of that came back. Two reasons, both visible in the
generated C. Packing four digits into a word costs shifts and ors the ablation
did not pay, because folding with xor is cheaper than assembling a word. And
the store still carries its bounds checks; only their number fell.

**What the generated C says is next.** The loop body is three word loads, the
arithmetic, four stores -- and *sixteen* `ks_lua_string_byte` calls, each
bounds-compared against a runtime length, because the alphabet has to arrive
as an argument. A `const` string would be a `static const unsigned char[]` with
a bound the C compiler holds, which is what `nupp.data.digest` gets for its
round constants. That route is the one that crashes the lowerer.

So the next factor is not a new operation. It is the `const`-string defect this
spike already found, and the workaround for it is what is now paying 16 checked
loads per twelve input bytes.

## The alphabet as a `const`

With the helper-scope defect fixed, the alphabet is a `const` again rather than
an argument. That changes what the bound is: `ks_length_konst_0` is a
`static const size_t` the C compiler holds, where a rooted argument's length is
a field loaded per call.

| bytes | aot | words | stores | const | w-nostore | c-scalar | c-vector |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 64 | 6.788 | 6.258 | 6.214 | 6.125 | 6.122 | 5.408 | 5.277 |
| 1,024 | 1.146 | 0.913 | 0.809 | 0.702 | 0.646 | 0.565 | 0.370 |
| 65,536 | 0.818 | 0.571 | 0.464 | 0.368 | 0.289 | 0.238 | 0.045 |
| 1,048,576 | 0.876 | 0.591 | 0.488 | 0.397 | 0.286 | 0.234 | 0.040 |

**Worth 1.26x, and it very nearly clears step one's gate.** That gate was the
entry within 1.5x of scalar C at 64 KiB. It now stands at 1.55x, against 1.93x
before. The check itself did not go away -- the index is a runtime value, so
the compare stays -- but its bound stopped being a load.

Cumulative over the three changes the entry is 2.21x its original self, and
9.9x off the vectorized ceiling where it began at 21.5x. What remains is 1.55x
of scalar overhead and 5.9x of vectorization.

## Against memcpy, which is the paper's yardstick

| bytes | const | c-scalar | c-vector | memcpy |
| --- | --- | --- | --- | --- |
| 1,024 | 0.750 | 0.582 | 0.379 | 0.35 |
| 65,536 | 0.426 | 0.260 | 0.048 | 0.02 |
| 1,048,576 | 0.453 | 0.252 | 0.044 | 0.01 |

Read the memcpy column as a generous floor rather than a fair one. The
benchmark copies the same buffer repeatedly, so at these sizes it is measuring
a cache-resident copy; the paper is careful to specify data that does not fit
in L1 for exactly this reason.

Even so it settles the question the spike was named after. **Nothing here
encodes base64 at close to the speed of a memory copy.** The vectorized C
control is 4.4x memcpy at 1 MiB, which does reproduce the 5.7x-over-scalar
result the literature claims for the algorithm. The compiled Nupp entry is
45x memcpy. What separates the two is the 5.7x that is vectorization, and
that is the only remaining factor that needs an operation which knows what a
vector is.

## The vectorized kernel

`bench/base64simd` encodes through the SIMD vocabulary: a three-lane strided
load de-interleaves the byte groups, shifts and masks produce four six-bit
indexes, one sixty-four entry lookup maps them to the alphabet, and an
interleaving store writes the quantum. Forty-eight input bytes per iteration.

| bytes | aot | const | nupp-simd | c-scalar | c-vector | memcpy |
| --- | --- | --- | --- | --- | --- | --- |
| 64 | 6.698 | 6.049 | 5.976 | 5.487 | 5.374 | 5.373 |
| 1,024 | 1.132 | 0.697 | 0.450 | 0.568 | 0.377 | 0.347 |
| 65,536 | 0.807 | 0.371 | 0.118 | 0.237 | 0.044 | 0.015 |
| 1,048,576 | 0.847 | 0.381 | 0.157 | 0.232 | 0.039 | 0.012 |

**It beats hand-written scalar C.** 0.118 against 0.237 at 64 KiB, and 0.157
against 0.232 at 1 MiB. Against the entry this spike started with it is 6.8x at
64 KiB. Against the vectorized C control it is 2.7x at 64 KiB and 4.0x at 1 MiB.

**The instruction mix is already the right one.** Disassembling the loop gives
one `ld3`, four `tbl` and one `st4` per iteration -- exactly what the C control
compiles to. Clang folded the three strided loads into a single `ld3` on its
own, which is why the vocabulary did not need a three-register type to express
the de-interleave.

So what remains against the control is not instruction selection. The next
section says what it is, and it is not what this paragraph originally guessed.

## The remaining gap was the benchmark, not the code

The guards looked like the answer and are not. Ablating them -- the strided
load's span check, the interleaved store's bound and straddle checks -- moves
the encoder by nothing outside noise. Two earlier ablation runs appeared to
confirm that at zero cost each; both were measuring a stale artifact, because
a bench build directory survives a compiler change. Every ablation here now
clears `build/` first, and the one that finally failed at run time is what
exposed the other two as meaningless.

What the gap actually was: the Nupp entry allocates its output buffer on every
call and first touches every page of it. The C control was being handed one
buffer allocated once and reused for every iteration of the timing loop. That
is not a comparison between two encoders.

`cv-fresh` is the same C control allocating per call, which is the honest
comparison:

| bytes | nupp-simd | alloc-only | cv-warm | cv-fresh | simd/fresh |
| --- | --- | --- | --- | --- | --- |
| 1,024 | 0.428 | 0.364 | 0.365 | 0.412 | 1.04 |
| 65,536 | 0.073 | 0.027 | 0.044 | 0.122 | 0.60 |
| 1,048,576 | 0.129 | 0.004 | 0.040 | 0.156 | 0.83 |

**The kernel is at parity with the C control, and ahead of it on the payloads
that matter.** The instruction mix was already identical -- one `ld3`, four
`tbl`, one `st4` in both, neither unrolled -- and once the allocation is
matched the timings agree.

`alloc-only` allocates the buffer and writes one byte, so it excludes the
first-touch cost of the pages the encoder actually writes; that is why it reads
as nearly free while the allocation is not.

Tightening the output bound from `2n + 4` to `1.5n + 4` -- still no division,
a quarter fewer bytes -- took the 64 KiB encode from 0.113 to 0.073, which is
1.5x for one line. That is the shape of what is left here: fewer bytes
allocated and touched, not fewer instructions executed.

## Shares, and a correction

The `cv-fresh` column above allocated `2n + 4` while the kernel had been
tightened to `1.5n + 4`, so it was paying for a larger buffer than the thing it
was being compared against. With the two matched, the earlier reading that the
kernel was *ahead* of the C control does not survive. It is behind it.

Three consecutive runs, matched allocation:

| bytes | alloc + first touch | encoding | nupp-simd as % of C control |
| --- | --- | --- | --- |
| 64 | 6-7% | 93-94% | 105% |
| 1,024 | 9-11% | 89-91% | 108% |
| 65,536 | 17-27% | 73-83% | 127-152% |
| 1,048,576 | 61-62% | 38-39% | 119-122% |

The 64 KiB row is the unstable one and should be read as a range rather than a
number; the others repeat to within a point.

**Allocation dominates at 1 MiB and is minor below 64 KiB.** Sixty-one percent
of the C control's per-call time at 1 MiB is allocating the output buffer and
taking the page faults for it, and only thirty-nine percent is encoding. That
is why the bound mattered more than any instruction did.

**These percentages are sensitive to the allocator, not just to the code.**
`2n + 4` on a 64 KiB input asks for 131,076 bytes, just past the 128 KiB
boundary where the allocator changes strategy; `1.5n + 4` asks for 98,308 and
does not. Most of what the tightened bound bought at that size was crossing
back over that line rather than moving a quarter fewer bytes.

## Improvement over the first working entry

Same runs, against the byte-at-a-time entry this spike started with.

| bytes | best scalar | vectorized |
| --- | --- | --- |
| 64 | 11% | 12% |
| 1,024 | 39% | 60% |
| 65,536 | 54% | 90% |
| 1,048,576 | 55% | 86% |

## Reusing the scratch

Allocation was 61 to 68 percent of the encode at 1 MiB, so the buffer is now
taken from a one-slot cache instead of allocated per call. Two runs:

| bytes | aot | const | nupp-simd | alloc-only | cv-warm | cv-fresh |
| --- | --- | --- | --- | --- | --- | --- |
| 65,536 | 0.661 | 0.323 | 0.075 | 0.006 | 0.045 | 0.055 |
| 1,048,576 | 0.668 | 0.325 | 0.069 | 0.000 | 0.039 | 0.123 |

**The vectorized encode is 0.069 ns per byte at 1 MiB, from 0.117.** Every
scalar entry moved with it, because they all publish from a byte scratch:
`aot` from 0.847 and `const` from 0.381. `alloc-only` reaches zero, which is
the whole point of the change.

Against the megabyte payload this spike started at 0.847, so the encoder is
now 12x that entry and about 5.6x the best scalar Nupp.

**What makes it safe is a compile-time refusal, not a runtime check.** A cached
buffer is handed back at the publish, which is only correct if nothing writes
it afterwards. The emitter proves that per entry -- one publish in the whole
program, at the top level, with nothing but returns after it -- and every entry
that fails the test keeps allocating. A decoder that publishes a string and
fills again is exactly the case that must fail it, and
`aotclitest.onlySinglePublishEntriesReuseAByteScratch` pins both answers.

## The control was not building its string

Profiling the encoder at 1 MiB put 59 percent of samples in the compiled entry,
15 percent in `_platform_memcmp` and 11 percent in `__munmap`. The memcmp is
LuaJIT interning the result: the benchmark encodes the same payload every
iteration, so the 1.4 MB result matches an interned string and is compared
against it in full each time.

Profiling the C control the same way put 3403 of 3404 samples inside
`nuppBase64EncodeVector` and none in interning -- because LuaJIT had
eliminated the `ffi.string` whose value nothing read. Making the result live
moved the control to 60 percent encoder and 40 percent memcmp.

`measure` discarded results in exactly the same way, so the control was excused
from building the Lua string that a compiled entry has no way to avoid
building. It now reads one byte of each result, which costs the same on both
sides. What that changes:

| 1 MiB | discarded | consumed |
| --- | --- | --- |
| nupp-simd | 0.069 | 0.091-0.101 |
| cv-warm | 0.039 | 0.087-0.091 |
| cv-fresh | 0.123 | 0.195-0.211 |

**The control more than doubled and the entry did not.** On equal terms the
vectorized entry is 1.05 to 1.11x the C control at 1 MiB and 1.11x at 64 KiB,
where the same comparison read as 1.8x before. Roughly half of what is left is
the bounds guards, measured separately at 8 points.

Every ratio recorded above this section was taken with results discarded and
therefore flatters the control. The absolute Nupp numbers stand; the
comparisons do not.

## What the guards actually cost

Ablating the bounds checks moved the encode by about 8 points, which read as a
modest cost with an obvious fix. Both halves of that were wrong.

The disassembly said what it was. The loop reloaded its 64-byte lookup table
from the stack on every iteration -- `ld1.2d { v20, v21, v22, v23 }, [x8]`
ahead of the four `tbl` -- where the C control keeps the same table in
registers for the whole loop. A `TableU8x64` value whose C representation is
the register quad was built to fix that, and did not: the generated loop came
out byte-identical, because the operand shape was never what decided it.

What decided it was the guards, in a way that ablating them measures only by
accident. Each guard called `luaL_error` inline, so the error path sat in the
hot block and the scratch struct stayed live across a call, and the register
allocator answered by spilling the loop-invariant table. Routing every guard
through one `noinline cold` raiser and marking the conditions unlikely moves
the error path out of line: the checks are all still there and still checked.

| | before | after |
| --- | --- | --- |
| loop body | 23 instructions | 17 |
| table reload | every iteration | hoisted |
| 64 KiB | 0.076 | 0.070 |
| 1 MiB | 0.071 | 0.065 |

That is the whole remaining distance to the C control, and it closes it: the
entry and the control now measure the same at both sizes. The lesson is that
an ablation prices the work a guard does, and misses the work a guard makes
the register allocator do.
