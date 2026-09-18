# Fused JSON decode, arm64 macOS

## What stands

The vector-algebra rewrite of the fused scan (`simd-fused-json`) is slower
than `main` on every input class, and on multi-byte UTF-8 it is slower by
almost seven times.

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
