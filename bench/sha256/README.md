# SHA-256 benchmark

Four implementations of one digest, measured against each other in one process.

- **Nupp `@aot`** — [`nupp.data.digest`](../../src/nupp/data/digest.nupp) built by
  the `sha256` target, which compiles the `@aot` entry and enters it as a
  registered Lua C closure.
- **Nupp on LuaJIT** — the same source built by the `sha256-scalar` target,
  which leaves it to LuaJIT.
- **C** — `sha256_control.c`, which was `nupp.data.sha256` before the Nupp
  implementation replaced it. Nothing in Nupp builds it any more; it lives here
  for the same reason `legacy.lua` does, and goes when this benchmark does.
- **Lua bit ops** — `legacy.lua`, frozen from what
  `nupp.compiler.build.hash.sha256` was. It is on no path any more; do not fix
  it and do not make it faster. Its value is being exactly what was measured
  before.

```sh
./run.sh
```

builds both targets, runs the differential tests, and reports. Add `--bench`
to follow them with the measurements, or run the harness directly:

```sh
LUA_PATH='build/aot/?.lua;build/aot/?/init.lua;../../.rocks/share/lua/5.1/?.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit benchmark.lua 15
```

`--json` before the sample count keeps the raw per-sample rates, the bootstrap
intervals and the toolchain identity; `NUPP_SHA256_BENCH_OUTPUT` writes that
report to a file without shell redirection.

## Protocol

Implementations alternate within a sample, so a machine that drifts drifts
through all of them equally. Call counts are calibrated per implementation to
about fifty milliseconds a sample, because the four here are two and a half
orders of magnitude apart and one byte budget cannot serve them; a sample is
therefore a throughput, and the reported ratio is a ratio of throughputs
bootstrapped over the paired samples. Every implementation must agree on a
payload before any of them is timed.

## Results

Apple arm64, clang `-O3`, fifteen paired samples. Committed at
`results/arm64-macos-int32.json` with the per-sample rates and the bootstrap
intervals.

| payload | Nupp `@aot` | Nupp on LuaJIT | C | Lua bit ops |
| --- | ---: | ---: | ---: | ---: |
| 32 B | 178 MB/s | 17 MB/s | 183 MB/s | 4.8 MB/s |
| 1 KiB | 403 | 68 | 406 | 10.3 |
| 64 KiB | 429 | 77 | 426 | 11.2 |
| 1 MiB | 430 | 77 | 419 | 11.2 |
| **geometric mean over the three large payloads, against C** | **1.008x** | **0.178x** | 1.000x | 0.026x |

Per payload against the colocated control: 1.028x on 1 MiB, 1.005x on 64 KiB,
0.992x on 1 KiB, 0.957x on 32 bytes. The short call is no longer the odd one
out, and getting it there is the part worth reading.

**The short call was never the Lua/C boundary.** The entry is cheap: the same
call, with the same argument checks and the same sixty-four-character result
pushed, returns in 17 ns when the body does no hashing, against 180 ns for the
control doing the whole digest. Twice this benchmark's notes blamed the
boundary, and twice the measurement said otherwise.

It was three things, each found by ablating the generated C and each fixed by
saying something the source had left unsaid.

First, the caller assembled the final block -- the remainder, the terminating
bit, the padding, the length in bits -- as a Lua string and passed it in. Five
interned allocations a call, 60 ns of 320. The entry builds it itself now.

Then, with the ablation repeated on what was left, the 32-byte call stood at
291 ns against 183:

| generated C | ns/call | vs C |
| --- | ---: | ---: |
| as emitted | 291 | 0.62x |
| the tail buffer on the C stack | 245 | 0.75x |
| the hex buffer on the C stack | 258 | 0.72x |
| both on the C stack | 219 | 0.84x |
| and the byte-scratch bounds checks off | 191 | 0.95x |

Two `lua_newuserdata` calls a digest, worth about 72 ns, and the checks on those
buffers, worth about 28 ns. Both are what an *appending* buffer costs: its
storage is sized at run time so it has to be allocated, and its bound is a
length that moves so it has to be loaded. Neither is true of these two buffers,
whose capacities are written in the source and which no caller can reach.

So `valuebuilder.newFixedByteScratch` says that, and the backend can then put
the storage in a C array at the call site and compare against the literal. The
entry allocates nothing at all now -- not one `lua_newuserdata` -- and the
32-byte digest went from 291 ns to 179, against the control's 178. That is
parity, and it is the same move the word buffer made earlier, which is the
lesson: the cost was never in entering compiled code, it was in describing a
buffer more loosely than the program knew it to be.

**How the compression loop got there**, which is a separate story from the
short call, and worth reading because the ablation that motivated it pointed at
the wrong fix. Ablating the generated C one cost at a time on the 1 MiB
payload:

| generated C | vs C |
| --- | ---: |
| as emitted, before either change | 0.778x |
| bounds checks removed | 0.878x |
| and the round constants as a static array | 0.966x |

The constants landed first: a `const` bound to a string literal is placed in
static C data now, worth five points rather than the nine the ablation
suggested, because the ablation had already taken the bounds check off that
same read. That left the checks, and the obvious reading of the table -- ten
points sitting behind a range proof the compiler cannot do -- was wrong.
Re-ablating on the emitted C after the constants landed:

| generated C | vs C |
| --- | ---: |
| as emitted, bound is `scratch->length` | 0.847x |
| no bounds checks at all | 0.919x |
| **checks kept, bound is a literal `64u`** | **0.940x** |

Keeping the check and making its bound a compile-time constant beats deleting
the check. The cost was never the branch; it was that the bound was a field
load. A write through `scratch->words` may alias `scratch->length` as far as
the C compiler can tell, so it reloads the bound after every store, and a
dependent load in the middle of the round loop is worth more than a
well-predicted branch that never fires. Handed a constant instead, clang
discharges the comparison outright wherever the index is one it can follow, and
where it cannot the branch is still emitted and still refuses.

So there is no range analysis in the Nupp compiler and no soundness argument
resting on one. `valuebuilder.newFixedWordScratch(n)` is a buffer whose length
is its capacity from creation -- every word readable, zero until written, no
fill loop, no append protocol -- and `n` has to be a literal for `@aot` to take
it. That is all the backend needs to emit the bound as an immediate. The
refusal is unchanged on both routes, and `aotbuildtest`'s
`aFixedScratchIsZeroedAndStillRefusesAnIndexOutsideIt` reads one past an
eight-word buffer through an index the compiler cannot fold; removing the
refusal from the emitter makes it return adjacent memory and fail.

Where the capacity is a literal small enough to stand on the C stack, the buffer
now does: the emitter declares an array at the call site and points the scratch
at it. Nothing is allocated, nothing is keyed in the registry, and nothing is
rooted on the Lua stack, because a buffer that cannot escape the entry has
nothing for Lua to own. The bound stays a constant, so the paragraph above still
holds.

**The uncompiled route is a sixth of the C, and 6.3x the implementation it
replaced.** It was 0.004x when this benchmark was written, and the whole of
that was the AOT-admitted subset making every fixed-width operation a call:
about a thousand per block, which is more than LuaJIT's recorder will unroll,
so `luajit -jv` reported `loop unroll limit reached` and the body ran
interpreted. Three changes took it to 0.170x. The `i32` and `u32` members lower
to inline BitOp rather than calling out through the installed `nupp.math`; a
bitwise operator keeps the width its operands carried, which deleted every
laundering wrapper this module needed; and the unsigned normalisation is
`% 2^32` rather than a comparison, which is both branch-free and an expression,
and an expression is what could be inlined at all. The recorder now compiles
the compression loop.

Two costs remain on this route: the module's own single-return helpers are
still Lua calls where `@aot` inlines them, and every cursor and index in the
`valuebuilder` surface is a `uint32`, so a codec written against it does its
loop arithmetic in the more expensive representation.

The same algorithm written flat, with no helper calls, ordinary Lua numbers for
the cursors and `bit` primitives for the arithmetic, reaches 52 MB/s through
the same `valuebuilder` scratch, and 170 MB/s with the schedule in a plain Lua
table. That is the headroom, and it says the gap is the call layer rather than
the scratch.

## What the differential tests cover

`tests/run.lua` holds the four against the published vectors, then against each
other: every length from nothing to two hundred bytes, all 256 byte values with
an embedded NUL, and the sizes either side of every boundary the
implementations reason about — a whole block, the 56-byte point where the
length tally stops fitting, and the point where a second padded block becomes
necessary.

That last one earned its place. The first `int32` draft of the digest passed
the published vectors on LuaJIT and failed them compiled, because `@aot` lowers
`nupp.math.i32.wrap` to a C cast from `double`, and a cast of a value at or
above 2^31 to `int32_t` is undefined rather than modular. The vectors alone
would have caught it here; a version of this benchmark that only measured
would not have. The draft only reached for `wrap` because a bitwise operator
dropped the width of its operands, so the fix was to stop dropping it rather
than to route around the cast.
