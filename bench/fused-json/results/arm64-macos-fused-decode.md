# Fused JSON decode, arm64 macOS

Two measurements, newest first. The second exists because of the first: the
unicode row below is what sent the rewrite back to put UTF-8 validation into
the vectors, and the round after it is what says that worked.

# Second measurement: vector UTF-8 validation restored

## What stands

The rewrite (`simd-fused-json` at `da158a72`) is slower than `main` on every
input class, by between a tenth and a third. The unicode row, which was the
finding of the first measurement, is fixed: it moved from 0.14x to 0.86x.

Normalized to the colocated Lunajson control, rewrite over main:

| payload | main | rewrite | ratio | first measurement |
| --- | ---: | ---: | ---: | ---: |
| records | 4.93 | 4.08 | 0.83x | 0.84x |
| ascii | 16.62 | 10.99 | **0.66x** | 0.75x |
| unicode | 12.68 | 10.92 | **0.86x** | 0.14x |
| nested | 4.92 | 4.43 | 0.90x | 0.87x |
| small | 3.85 | 3.45 | 0.90x | 0.95x |

Geometric mean over the four large payloads: 0.81x, against 0.53x before.

Raw medians, each the median of two rounds of fifteen samples:

| payload | main MB/s | rewrite MB/s | lunajson main | lunajson rewrite |
| --- | ---: | ---: | ---: | ---: |
| records | 337.7 | 279.5 | 68.5 | 68.5 |
| ascii | 2857 | 2010 | 171.9 | 182.9 |
| unicode | 2306 | 2073 | 181.9 | 190.0 |
| nested | 118.4 | 107.1 | 24.0 | 24.2 |
| small | 214.2 | 192.2 | 55.7 | 55.8 |

## What fixed the unicode row

Two changes, and the second is the larger one.

The lookup4 validator went back in, on the same three nibble tables the block
scan used and `bench/utf8simd` spells with `swizzle`. And a non-ASCII byte
stopped being a structural event at all. It had been one only so the drain
could validate it, so a corpus that is forty percent non-ASCII drained forty
percent of its bytes through a per-byte state machine; nothing above the
validator needs to see one, because outside a string the tape walk refuses it
as the syntax error it is and inside a string it is only bytes.

## The ascii row, which got worse

It is the one row that moved the wrong way, 0.75x to 0.66x, and it is now the
weakest. The cause is not that the rewrite classifies UTF-8 on vectors that do
not need it: a vector with no non-ASCII byte, following another such vector,
already skips the lookups entirely. The cost is the *test* that decides that --
one `Mask.any` horizontal reduce per sixteen bytes, which the previous revision
did not pay because non-ASCII was folded into the event mask and read out by
the `bits` call the scan makes anyway.

Measured directly. Rebuilding the branch with that one test stubbed to `false`
and nothing else changed moves ascii from 10.99 to 13.07 normalized, which is
0.79x of main and slightly better than the 0.75x the first measurement had.
The reduce is therefore the whole of the regression. (The same probe's other
rows say nothing: with the test false the validator never runs. Only ascii is
readable from it, because on an all-ASCII payload that test answers false
anyway and the missing reduce is the only difference.)

No cheap recovery exists. Folding non-ASCII back into the event word removes
the reduce, because the scan already reads that word out -- and reinstates the
per-byte drain on every non-ASCII byte, which is exactly the unicode
regression. Detecting non-ASCII once per thirty-two bytes instead of sixteen
would halve the cost, but it means unrolling the loop to two loads and two
bitmask readouts, which is not a cheap change and was not made. The row is
recorded rather than optimized.

## Conditions

Load averages ran 2.8 to 4.1 (one minute) across the four rounds, higher than
the 2.07 to 2.25 of the first measurement, and both trees moved down with it:
`main`'s own ascii median fell from 3015 to 2857 MB/s between the two. That is
why every ratio here is against the Lunajson control measured in the same
process on the same bytes, and why the raw columns are reported beside it
rather than instead of it.

Rounds ran main / rewrite / rewrite / main, fifteen samples each, one after
another on an otherwise unchanged machine. The two rounds per tree agree
within 2.5 percent on every payload except the rewrite's `small` (3.56 and
3.33), which is the row where a decode is mostly call overhead.

| | main | simd-fused-json |
| --- | --- | --- |
| source | `c4a0a94d` | `da158a72` |
| decoder source sha256 | `dd790b7b…` | `ed079dc1…` |

The first measurement's baseline worktree had never had the repository built
into it, so the vendored Lunajson control was missing and all four of its
`main` rounds died in `require`; the rounds above were taken after a full
`./bin/nupp build` there and a standalone `run.sh` check.

## The signature workaround is no longer needed

Both measurements were taken through `prepare.sh`'s narrowing of the entry to
`source: string`, because a `borrows source: string | Buffer` parameter did
not survive the generated ahead-of-time wrapper. `Carry ownership contracts
onto generated AOT wrappers` fixed that after these rounds were taken: the
decoder's entry now compiles unmodified, emitting the same vector scan from a
signature that still says `borrows`.

Nothing above changes -- both trees got the identical edit, so the comparison
stands -- but the next measurement can drop the workaround, and doing so would
cover the two things this one does not: the `Buffer` input path and the public
`nupp.codec.json.decode` dispatch in front of the entry.

# First measurement: the scalar-validation rewrite

| payload | main MB/s | rewrite MB/s | rewrite / main |
| --- | ---: | ---: | ---: |
| records | 360.6 | 304.4 | 0.84x |
| ascii | 3,015 | 2,353 | 0.78x |
| unicode | 2,446 | 363 | **0.15x** |
| nested | 130.1 | 115.6 | 0.89x |
| small (30 bytes) | 233.5 | 228.3 | 0.98x |

Normalized to the colocated Lunajson control -- which moved between 1 and 5
percent across the runs, and moved *in the rewrite's favour* every time -- the
four large payloads' geometric mean is 0.53x. The rewrite is about 1.9x
slower end to end on this corpus.

The 30-byte payload is the one place the two agree. At that size the decode is
call overhead and neither scan reaches a second vector, which is what makes it
the control for everything above it: a change that only moved per-call cost
would have moved this row too, and it did not.

The unicode row is the finding. `main` classifies UTF-8 with simdjson's
lookup4 tables out of the bytes already in the vector; the rewrite validates
scalar, one byte at a time, for every non-ASCII byte. The corpus is about
forty percent non-ASCII, and the decode falls from 2,446 to 363 MB/s -- below
twice Lunajson, which is a pure-Lua decoder. Nothing else in the comparison is
close to this.

The other three large rows are the expected cost of 16 bytes per iteration
instead of 64 and a scalar per-event drain instead of a native bulk tape
drain: 0.78 to 0.89x, consistent across rounds, and the same direction
everywhere.

## Provenance

| | main | simd-fused-json |
| --- | --- | --- |
| source | `4e72476a` (bench on `main`) | `df9fa9ca` (bench on `b26bde39`) |
| decoder source sha256 | `c31cda5a…` | `84b71d31…` |
| generated Lua sha256 | `feee4e24…` | `8dd3962c…` |
| compiled object sha256 | `10fd9792…` | `e7b48070…` |

Same machine, one after another, in the order main / rewrite / rewrite / main.

- Target `aarch64-apple-darwin`, Darwin 25.6.0, Apple silicon. NEON feature
  tier; `simd.preferredU8` is 16 lanes.
- Compiler: `nupp 0.0.9-dev`, each tree built from its own `src` -- the two
  differ only in the decoder and its test, so the compilers are otherwise the
  same program.
- Build: `kind = "modules"`, `aot = "require"`, `optimize = 1`. Native leg is
  Apple clang 21.0.0.
- Host: LuaJIT 2.1.1787165859.
- Reference column: the vendored Lunajson decoder
  (`nupp.runtime.vendor.lunajson.decoder`), in the same process, on the same
  bytes.

Load averages were 2.07 to 2.25 (one minute) throughout; another agent was
compiling on the machine for the whole window and it never went quiet. That is
why every number here is a median over fifteen samples, why the two
implementations alternate inside each sample, why the rounds alternate which
checkout leads, and why the Lunajson column is reported beside every figure.
The four rounds agree within 1.5 percent of each other, and the control moved
less than the effect by an order of magnitude on the unicode row.

## Inputs

All five are deterministic, so two checkouts decode the same bytes. Digests
are FNV-1a/32 over the payload, printed by the harness.

| payload | bytes | digest | what |
| --- | ---: | --- | --- |
| records | 2,097,203 | `1d8700b7` | dense record objects, mixed scalars |
| ascii | 2,097,217 | `7b49ddf0` | plain ASCII string values |
| unicode | 2,097,192 | `c9a0b750` | two, three and four byte UTF-8 |
| nested | 2,097,881 | `0b6138c0` | deeply nested containers |
| small | 30 | `15e3b2e4` | one object per call |

Escaped strings are not covered here. `main`'s README records that corpus as
the one where the two halves of validation and transformation were fused, so
it is the obvious next payload to add; it is not what this comparison was
asked about.

## The statistics

Fifteen samples per implementation per payload per round, two rounds per
checkout, about 2 MB moved per timed batch. Medians with the sample range:

| payload | main median (min-max) | rewrite median (min-max) | lunajson main | lunajson rewrite |
| --- | --- | --- | ---: | ---: |
| records | 362.1 (356-375), 359.2 (347-369) | 306.3 (300-313), 302.4 (286-307) | 74.0, 72.6 | 74.2, 73.9 |
| ascii | 3013 (2921-3102), 3018 (2885-3080) | 2364 (2277-2430), 2341 (2099-2400) | 189.4, 177.1 | 192.0, 190.3 |
| unicode | 2444 (2383-2473), 2447 (2349-2470) | 361 (354-369), 365 (354-378) | 199.0, 182.9 | 202.3, 199.3 |
| nested | 130.7 (109-134), 129.4 (99-135) | 115.8 (99-121), 115.4 (101-119) | 25.9, 25.3 | 26.2, 26.0 |
| small | 234.7 (229-240), 232.2 (223-234) | 228.7 (226-235), 227.8 (223-234) | 58.5, 58.4 | 60.0, 60.4 |

Normalized to the colocated control, rewrite over main: records 0.84x, ascii
0.75x, unicode 0.14x, nested 0.87x, small 0.95x. Geometric mean over the four
large payloads, 0.53x.

## What the harness had to work around

Nothing in this repository builds `nupp.codec.json` ahead of time -- no target
in the root manifest sets `aot`, so the compiled decoder is only ever produced
by a downstream project. That path does not check today, and both branches
fail it identically:

1. A const-generic `@aot` declaration keeps its authored signature in the
   generated dispatcher, but the private wrappers the dispatcher forwards to
   are emitted without parameter contracts. Forwarding `borrows source` into a
   parameter that declares none is NUPP2603, reported against a line of
   `fused.nupp` nobody wrote, because the position is in the rewritten source
   and the caret is rendered from the file on disk.
2. Declaring `borrows` on those wrappers instead moves the failure one step:
   the Lua-builder wrapper hands its source to a registered builder through an
   `any`-typed local, and NUPP2611 refuses a live capability crossing an
   untyped call. There is no spelling that gets past it -- `unsafe release`
   wants an affine value and a borrow is not one, `as any` inside `unsafe do`
   keeps the tracking, and a function type cannot carry `borrows`.

`fused.nupp` is the only `string | Buffer` `@aot` entry in the tree, so this
has presumably never worked. Tracked at
https://github.com/nupp-lang/nupp/issues/55.

Fixed since this run. `binding.logical` restates `borrows` on a
string-or-buffer wrapper parameter, and the loaded builder is now declared
with a contract-carrying function type instead of `any`. A function type can
carry `borrows` after all; only the unnamed spelling is a parse error, and
`function(borrows source: string | Buffer): any` is not. `prepare.sh` keeps the
narrowing regardless, so the numbers above and the numbers a later tree
measures compare against the same rewrite.

`prepare.sh` therefore narrows the copied entry to `source: string` and swaps
`paddedBytesU8` for `paddedStringU8`, which is the same native input. Both
trees get the identical edit, so the comparison is unaffected; what is not
measured here is the Buffer input path and the public
`nupp.codec.json.decode` dispatch in front of it.

## Proving the compiled decoder is what ran

The harness prints three facts before its first timing and refuses to measure
without them: the artifact `require` loaded carries `ks___nupp_const_decode_fused`
and `__nuppAotCompiled` and no longer carries the authored scan, the
replacement registry is populated, and every registered builder is a C
function (`debug.getinfo(fn).what == "C"`) out of the compiled object. The
generated module is 264 lines against 852 of source and the object is 200 KiB,
which is the other half of the same statement.
