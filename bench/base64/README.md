# base64

A spike. It exists to put a number on one question: what would the SIMD
operations a base64 codec needs actually be worth, given that `nupp.simd` has
none of them.

Nothing here is on a hot path. `nupp.runtime.browser.base64` is the only base64
Nupp ships, it is browser-only, and its cost is the Lua layer rather than the
codec. Deleting this directory removes the experiment and no compiler feature,
which is the test [NEP 11](../../docs/neps/0011-simd.md) sets for a workload.

```sh
./run.sh
```

Correctness is checked against a third implementation written in the harness,
over every input length from 0 to 200, so a shared bug in the two
implementations under test cannot agree its way past it.

## The gate, declared before measuring

Continue to compiler work only if the vectorized C beats the scalar C by at
least 4x on payloads at or above 64 KiB. Below that the ceiling does not pay
for an instruction surface.

**It passed: 5.87x at 1 MiB.** See [the results](results/arm64-macos-encode.md).

## What it found instead

The gate was aimed at the wrong thing. Almost none of the distance to the
vectorized ceiling was vectorization.

Three quarters of it closed before a single vector operation existed. Reading
whole words instead of single bytes was worth 1.42x and needed no compiler
change at all -- `valuebuilder.word` already existed and `nupp.data.digest`
already used it. A word-wide store, a fixed `const`-string defect, and
reusing the output buffer instead of allocating it per call took most of the
rest. Only the last factor, about 5.7x, was ever about instructions.

The vectorized kernel exists now, in [`../base64simd`](../base64simd), and the
operations it needed landed with it: the vocabulary had no store of any kind
before this spike. What it is worth against hand-written C, and what remains,
is in [the results](results/arm64-macos-encode.md) -- read that rather than
this paragraph, because the comparison moved several times and the document
records which readings survived.

## Two defects found while writing it

Both are in the AOT lowering, both were hit by ordinary source, and neither is
about base64.

**Reading a `const` string inside a helper crashed the compiler.** Fixed. The
first diagnosis here was wrong and is worth recording as such: it was not
specific to `valuebuilder.byte`, and `valuebuilder.word` was not immune.
Neither accessor mattered. What mattered was that the read sat inside a local
helper rather than in the entry body, and the verifier seeded a helper's scope
from its parameters alone, so a compile-time byte table -- file-scope static
data the emitted helper can read perfectly well -- was a name it had never
heard of. The entry's scope had always carried them.

**A rooted byte access from a parameter cannot sit behind a helper.** `valuebuilder.byte`
requires its first argument to be a local of the entry itself, so wrapping the
alphabet lookup in a one-line helper is refused. That one is a diagnostic and
says so clearly; it is recorded here because it is why the lookup is written
out at each call site rather than named once.
