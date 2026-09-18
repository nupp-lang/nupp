# UTF-8 validation, four ways

What `nupp.text.utf8.isValid` is worth written four different ways, on one
machine in one run: the Keiser-Lemire lookup validator written on the general
`nupp.simd` algebra, the same scalar ladder compiled by `@aot` and left to
LuaJIT, the ordinary Nupp that ships.

```sh
./run.sh          # in-process, all four interleaved
```

`tests/one.lua` runs one implementation over one corpus in a process of its own.
Prefer it for anything but the two compiled entries: four validators in one
process is four sets of traces competing for the same specialization, and the
ones that are Lua read low there. A compiled entry is a registered C closure and
does not care either way.

## What it found

Best of seven, one implementation and one corpus a process, against the shipped
Nupp implementation. Apple M5 Pro, `aarch64-apple-darwin` with NEON, Apple
clang 21.0.0 at the compiler's default flags, LuaJIT for the three columns that
are Lua; measured 2026-09-17.

| corpus                 |  SIMD | `@aot` | `@aot` on LuaJIT | `nupp.text.utf8` |
| ---------------------- | ----: | -----: | ---------------: | ---------------: |
| short ascii (8-24 B)   | 1.59x |  0.58x |            0.14x |            1.00x |
| short accented (~20 B) | 1.53x |  0.68x |            0.12x |            1.00x |
| short CJK (~24 B)      | 2.19x |  0.70x |            0.30x |            1.00x |
| json-ish 4 KiB         | 12.9x |  1.34x |            0.05x |            1.00x |
| CJK 900 B              | 5.43x |  0.94x |            0.19x |            1.00x |
| ascii 1 MiB            | 14.2x |  1.34x |            0.05x |            1.00x |

In MB/s, the SIMD column before and after it was rewritten from the byte-only
API (`simd.preferredU8`, sixty-four-byte padded blocks) onto the general
`nupp.simd` algebra (a `uint8` species, `swizzle`, `align`, loads straight from
the string), same machine, same run, one process per number:

| corpus                 | byte API | general algebra |
| ---------------------- | -------: | --------------: |
| short ascii (8-24 B)   |      889 |            2889 |
| short accented (~20 B) |      788 |            2111 |
| short CJK (~24 B)      |      962 |            3455 |
| json-ish 4 KiB         |    10441 |           34257 |
| CJK 900 B              |    10158 |           11004 |
| ascii 1 MiB            |    10574 |           38610 |

Three answers, and they no longer point the same way they did.

**On a buffer, SIMD is five to fourteen times the shipped implementation.** A
scalar validator spends most of its time on continuation bytes and the lookup
validator does not care. ASCII gained the most from the rewrite: the byte API
copied every string into padded sixty-four-byte blocks before looking at it,
where the general algebra loads sixteen bytes at a time from the string as it
stands, and an all-ASCII vector costs one compare and one reduction. Dense CJK
gained least because every vector of it takes the full lookup either way.

**The scalar `@aot` entry modestly beats the shipped implementation on large
buffers.** Validation is a branch a byte with no arithmetic to speak of;
`bench/sha256` found a larger compiler gain because a digest is arithmetic.

**Short values are where the answer changed.** The byte API lost on eight to
twenty-four bytes -- the species, three nibble tables and a padded copy were
set up to validate twenty bytes -- and that was the finding that kept
`nupp.text.utf8` ordinary Nupp. On the general algebra the same tables are
sixteen `insert`s into a zero vector and there is no copy, and the compiled
validator is now one and a half to two times the shipped one even there. The
Lua-to-C boundary is what remains of the cost, and the scalar `@aot` column
says what that boundary is worth on its own.

What still holds `nupp.text.utf8` to ordinary Nupp is the fallback: a target
without an AOT policy would get the scalar entry as LuaJIT runs it, which is
seven to twenty times worse than what ships. The shape a compiled validator
would take is `nupp.codec.json`'s: a seam with the compiled validator behind it
and the portable one underneath, not a replacement.

## Why the SIMD validator is its own project, beside this one

`bench/utf8simd` builds under any AOT policy now -- the general algebra has a
scalar continuation, so a target with `aot = "off"` checks the file -- but it
stays a separate project because a project reaching the compiler's `src` from
one level deeper writes its generated C into its own source tree instead of its
build directory.

The vector loop runs while a whole vector remains and answers which vector holds
the first error; a lead in the last three lanes of the final vector has its
continuations outside it, so the tail rewinds to the last byte that could begin
a scalar and finishes on the scalar ladder. `bench/utf8simd/tests/run.lua` holds
the vector path to an independent table-driven reference, byte position by byte
position: every scalar and every malformed sequence at every offset through
three vectors and a tail, every cut through each, and every corruption and
truncation of a multibyte string. `bench/utf8simd/run.sh` runs it.

## What the port ran into

The shape of the body was most of the scalar answer. The first version carried a
`bad` flag to a single exit; rewriting it to return from wherever it finds out
took a megabyte of ASCII from 2.0 GB/s to 4.1. Per
ASCII byte the flag form set four locals and tested three, where the ladder
tests one byte and advances.

`valuebuilder.byteAt` needs its bound in the positive form, with the read in the
true arm. A guard clause is refused, so the continuation reads stay checked and
only the lead byte is `bytes[at]`. Making all four unchecked was worth nothing
on ASCII and about a tenth on dense CJK, which is why the guard form wins here.
