# UTF-8 validation, five ways

What `nupp.data.utf8.isValid` is worth written five different ways, on one
machine in one run: the lookup4 SIMD validator `nupp.simd` carries, the same
scalar ladder compiled by `@aot` and left to LuaJIT, the ordinary Nupp that
ships, and the `lua-utf8` rock the module used to call.

```sh
./run.sh          # in-process, all five interleaved
```

`tests/one.lua` runs one implementation over one corpus in a process of its own.
Prefer it for anything but the two compiled entries: five validators in one
process is five sets of traces competing for the same specialization, and the
ones that are Lua read low there. A compiled entry is a registered C closure and
does not care either way.

## What it found

Best of seven, one implementation and one corpus a process, against the rock:

| corpus                 |  SIMD | `@aot` | `@aot` on LuaJIT | `nupp.data.utf8` |  rock |
| ---------------------- | ----: | -----: | ---------------: | ---------------: | ----: |
| short ascii (8-24 B)   | 0.61x |  0.74x |            0.20x |            1.29x | 1.00x |
| short accented (~20 B) | 0.57x |  0.74x |            0.20x |            0.64x | 1.00x |
| short CJK (~24 B)      | 0.60x |  0.70x |            0.24x |            0.96x | 1.00x |
| json-ish 4 KiB         | 2.92x |  1.00x |            0.04x |            0.75x | 1.00x |
| CJK 900 B              | 4.18x |  0.76x |            0.11x |            0.88x | 1.00x |
| ascii 1 MiB            | 2.93x |  1.00x |            0.04x |            0.75x | 1.00x |

Three answers, and they do not point the same way.

**On a buffer, SIMD is three to four times the C.** 11.9 GB/s on a megabyte of
ASCII against the rock's 4.1, and 4.18x on dense CJK, where a scalar validator
spends most of its time on continuation bytes and lookup4 does not care. This is
the ceiling, and it is a long way above where the module sits.

**The scalar `@aot` entry ties the C** on the same buffers -- 4085 MB/s against
4088 -- and does not beat it. Validation is a branch a byte with no arithmetic
to speak of, so there is nothing for a C compiler to win that LuaJIT has not
already won; `bench/sha256` found the opposite because a digest is arithmetic.

**Every compiled form loses on short values.** 0.57x to 0.74x at eight to
twenty-four bytes, where the Lua-to-C boundary is most of the call and, for the
SIMD entry, the species, the three nibble tables and the padded string are set
up to validate twenty bytes. Short values are most of what a program validates.

So `nupp.data.utf8` stays ordinary Nupp. Not because the backend cannot do
better -- it can do three times better -- but because it would be slower at what
the module is actually asked to do, and a target without an AOT policy would get
the fallback, which is four to twenty-five times worse than what ships.

Where this would pay is a caller validating buffers rather than fields, and the
shape it would take is `nupp.data.json`'s: a seam with the compiled validator
behind it and the portable one underneath, not a replacement.

## Why the SIMD validator is its own project, beside this one

`simd.preferredU8` creates an AOT-only value, so a target with `aot = "off"`
refuses the source at check time -- NUPP2903, at the call. A project's `include`
covers every target in it, so the scalar target could not check that file
either. `bench/utf8simd` is a separate project for that reason, and the reason is the
finding: there is no uncompiled form of this validator to fall back to.

Whole blocks only. A lead byte in the last three positions of the final block
has its continuations outside it and no following block to carry them, so the
tail rewinds to the last byte that could begin a scalar and finishes on the
scalar ladder. The differential covers that: every corruption and every
truncation at every position of a multi-block string, and a two-, three- and
four-byte scalar deliberately straddling each of the first three block edges.

## What the port ran into

The shape of the body was most of the scalar answer. The first version carried a
`bad` flag to a single exit and ran at half the rock; rewriting it to return
from wherever it finds out took a megabyte of ASCII from 2.0 GB/s to 4.1. Per
ASCII byte the flag form set four locals and tested three, where the ladder
tests one byte and advances.

`valuebuilder.byteAt` needs its bound in the positive form, with the read in the
true arm. A guard clause is refused, so the continuation reads stay checked and
only the lead byte is `bytes[at]`. Making all four unchecked was worth nothing
on ASCII and about a tenth on dense CJK, which is why the guard form wins here.
