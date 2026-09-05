# SIMD JSON benchmark

This benchmark retains the Nupp AOT experiment, differential decoders, and
performance history behind `nupp.data.json.internal.decode`. Its C++ code is
an external simdjson control only; none of it is part of the production runtime.

The benchmark uses Nupp's deliberately narrow C++ binding to the system
`simdjson` package. It requires `pkg-config`, simdjson development files, and
LuaJIT development files (`brew install simdjson luajit` on macOS). The
benchmark wrapper retains stage-one and DOM calibration calls alongside the
control parsing and serialization operations:

- `simdjson_bench.decode(source, nullValue)` eagerly constructs ordinary Lua
  values through simdjson's DOM parser.
- `simdjson_bench.pull(source, shape, nullValue)` uses On-Demand without first
  constructing a simdjson DOM. `true` selects a complete value, an object-shaped
  Lua table selects named fields, and `simdjson_bench.arrayOf(itemShape)` applies
  one shape to every array member. `false` drops a value, so `arrayOf(false)`
  validates an array without retaining its members. Unselected values are still
  consumed and validated, but allocate no Lua values.
- `simdjson_bench.encode(value, nullValue)` (also named `serialize`) converts a
  Lua value to JSON with simdjson's low-level string builder.
- `simdjson_bench.writer(out, nullValue)` exposes the same builder incrementally
  over caller-owned storage. `startObject`, `startArray`, `key`, `write`, `null`,
  and `close` form a checked JSON stream. Values returned by `encoded` or
  `verified`, and strings returned by `encodedString` or `verifiedString`, skip
  repeated traversal, validation, and escaping.

JSON null is dropped by default: object members disappear and array members are
compacted. Passing any non-nil `nullValue` preserves null with that identity.
`EMPTY_ARRAY` and `EMPTY_OBJECT` are stable exported marker sentinels used by
both parsing paths and accepted by both serializers. Decoded empty containers
are ordinary fresh Lua tables carrying the corresponding marker as their
metatable. An unmarked empty Lua table encodes as an object; `asArray({})` marks
an empty array explicitly. Non-empty Lua tables must be either contiguous
one-based arrays or string-keyed objects.

```lua
local projected = simdjson_bench.pull(source, {
   id = true,
   profile = {name = true},
   tags = simdjson_bench.arrayOf(true),
})

local out = require("string.buffer").new()
local writer = simdjson_bench.writer(out, myNull)
writer:startObject():key("id"):write(projected.id)
writer:key("items"):write(simdjson_bench.EMPTY_ARRAY):endObject()
writer:close()
local json = out:tostring()
```

The removed lazy-DOM prototype offered random access by constructing a complete
native DOM first. Pull shapes make the intended trade explicit: traversal is
forward-only inside one native call, while only selected application values
cross into Lua. This also prevents an On-Demand cursor or nested value from
escaping the parser and input-buffer lifetime that makes it valid.

These APIs inherit simdjson DOM number behavior. In particular, negative zero is normalized and an
out-of-range token such as `1e309` is rejected instead of producing infinity.

The production route has three stages inside one native entry:

1. `simd_json.fused` reads the Lua-rooted input with target-width packed bytes.
   Four native vectors classify a 64-byte block through simdjson's two nibble
   tables; prefix-XOR quote masks and bit-run escape detection classify strings.
   simdjson's lookup4 tables validate UTF-8 from the current bytes and the
   preceding three bytes without scanning each non-ASCII byte.
2. Structural words are appended to bounded Lua-rooted native scratch storage.
   A closing quote carries one tag bit when its string contains an escape, so
   the tape stays proportional to structural tokens rather than escape count.
3. The same VM-aware AOT entry consumes that scratch tape while streaming
   arrays, objects, strings, numbers, booleans, and null into final Lua values.
   There is no FFI array, rooted tape copy, node/link/frame arena, or second
   native crossing.
   Escaped strings copy and locate backslashes together in 16- or 32-byte
   vectors, then decode every escape found in that window without rescanning.
   Objects start with four hash slots. A top-level array starts with one slot
   per estimated 32 input bytes, capped at 262,144 slots; nested arrays start
   with four. These bounded hints replace the former serial capacity pass and
   affect allocation only, never parsing semantics. Escaped strings reuse one
   lazily allocated byte region before their final Lua-owned string copy.
   Number grammar, mantissa accumulation, conversion, and builder publication
   are one generated-C operation. Long digit runs consume eight bytes at a
   time after a cheap last-byte eligibility check. The common exact-power path
   remains one multiplication or division; the remaining 19-significant-digit
   range uses 128-bit power-of-five conversion with round-to-even. Only long
   or otherwise ambiguous mantissas retain the correctly rounded `strtod`
   fallback.

The production `nupp.data.json.pull` route drives the same entry with a selection
shape. It retains grammar state for every container but creates Lua tables and
values only for selected branches. Skipped escaped strings validate their escape
and surrogate structure without allocating transformed storage or an interned Lua
string; skipped numbers have already been grammar-validated while finding their
token boundary and do not run numeric conversion.

Selected object shapes are compiled into a bounded native key plan once per
distinct shape in a pull. Incoming keys compare directly from the source, or
from escape scratch when transformed, so rejected keys never become Lua
strings. A matched key reuses the shape's already-interned spelling, and the
result table is sized for the selection rather than the source object. Escape
scratch starts at the transformed slice instead of reserving the input's full
size, and grows only when a later selected string needs more room.

Inputs no longer than 32 bytes use the builder's sixteen inline frames. Larger
documents retain the authored nesting bound, allocating out-of-line frames only
if they actually cross the inline depth.

`simd_json.indexer`, `simd_json.parser`, and the former recursive Lua arena
materializer remain as explicit differential and benchmark controls.
`arena.decode` is not on the normal large-document path.

`simd_json.scanner` and `json.decodeLegacy` remain as the frozen J0 oracle and
benchmark baseline; they are no longer the large-document decode path.

Run the differential and public-runtime tests:

```sh
./run.sh
```

After building, measure classification, structural indexing, simdjson stage
one and internal DOM construction, eager Lua DOM construction, On-Demand pull
construction, selective Nupp pull construction, serialization, native arena
parsing, the old Lua materializer, and the legacy/arena/fused decoders:

```sh
LUA_PATH='build/?.lua;../../build/?.lua;../../.rocks/share/lua/5.1/?.lua;../../.rocks/share/lua/5.1/?/init.lua;;' \
LUA_CPATH='../../.rocks/lib/lua/5.1/?.so;;' \
luajit benchmark.lua
```

The harness alternates implementations, uses four warmups and fifteen paired
samples by default, and runs about 5 MB through each measured sample. It runs a
full Lua collection before each timed implementation, then leaves collection
enabled during that implementation. This keeps reclamation in the measurement
without making one implementation inherit the preceding one's allocation
debt. Pass `--json` before the optional sample count to retain raw seconds,
bootstrap confidence intervals, payload hashes, and toolchain identity:

```sh
luajit benchmark.lua --json 15
```

If `lua-cjson` is available on `LUA_CPATH`, the same run includes it as an
optional benchmark participant. It remains absent from the project dependency
graph. JSON output records paired Nupp/simdjson-Lua and Nupp/cjson ratios for
each payload plus their large-payload geometric means. The `unique-keys`
payload isolates rejection cost with thousands of distinct object keys and one
selected field.

## Where a decode's time goes

These shares were taken on Apple arm64 with temporary instrumentation: a stop
point on `fused.decode` that returned at each phase boundary, so subtracting
one timing from the next gave the phase between them, and ablations that ran a
whole decode with one cost dropped, so the difference was what that cost was.

**None of it is in the decoder now.** Six ablation flags sat in the hot loops,
two of them inside the innermost drain, and together they cost about five
percent of a decode -- enough to distort the next thing measured with them. A
measurement tool is not worth carrying in the path it measures. Restore it from
history when a figure below needs revisiting rather than trusting it twice.

Of the phases, materialization is 61 to 85 percent of every decode and
classification is 14 to 34, so the scan is the smaller half everywhere.
Allocating the structural tape is under 1.5 percent, because the scratch is
`lua_newuserdata` and is never zero-filled; first touching those pages is the
scan's cost. The former object-capacity pass was 13 to 16 percent of records and
near nothing elsewhere, since only a document with an object marker in its
first block ran it.

That pass is all fixed cost on a 30-byte object. In two exact-parent pairs with
fifteen samples, omitting it and the zero-capacity scratch allocations improved
public decode throughput from 84.8 to 121.7 MB/s and from 104.0 to 144.5 MB/s,
or 1.44x and 1.39x. The colocated simdjson control slowed in both pairs, so
machine drift cannot account for the gain.

Inside classification, working out the masks was 72 to 81 percent of the scan,
the lookup4 validator 4 to 18, and publishing the tape 10 to 29. The retained
64-byte nibble classifier addresses that largest part directly. In two
exact-parent pairs with nine samples and 2 MB per sample, it improved the five
large payloads' geometric mean by 1.18x and 1.12x raw, or 1.20x and 1.15x after
normalizing to the colocated simdjson binding.

Inside materialization, against a noise floor near two percent: interning a
string value's bytes is 35 to 40 percent of a decode, converting decimal
tokens was 41 percent of the numeric payload before the exact path and is 8
after, transforming escapes is 14 percent of the escaped payload, and
exactly presizing containers saved about 22 percent of records against the 13
to 16 its pass cost. Replacing both the serial pass and exact sizes with bounded
construction hints subsequently improved records another 1.18x and 1.19x in
two nine-sample comparisons, while the large-payload geometric mean improved
1.05x and 1.09x.

Escaped string values used to be validated twice: the authored materializer
walked the complete slice, then the builder walked it again while transforming
the escapes. Object keys already relied on that same builder validation. The
value-side preflight is now gone, so validation and transformation share one
pass. In two exact-parent A/B pairs on Apple arm64, nine samples and 2 MB per
sample, direct fused throughput improved 1.40x and 1.50x on the escaped corpus;
the colocated simdjson control moved less than four percent. The faster pair
reached 921 MB/s against simdjson's 1,473 MB/s, reducing that end-to-end gap
from 2.16x to 1.60x. The other four large payloads contain no escaped string
value, so no gain is claimed for them.

The subsequent cache-line rewrite keeps blocks containing backslashes on the
64-byte classifier. It applies simdjson's add-and-parity escape calculation to
one `MaskBits64`, then one native tape append marks closing quotes from the
slash mask without publishing every slash as an event. In two exact-parent
nine-sample pairs it improved escaped throughput 1.077x and 1.068x raw, or
1.146x and 1.140x after normalization to simdjson. The retained pairs reached
954 and 942 MB/s and reduced the colocated end-to-end gaps to 1.48x and 1.46x.
The first version drained each backslash through authored control flow and cut
escaped throughput in half; it was removed before the native append boundary
was introduced.

Two plausible follow-ups lost decisively. The earlier attempt to aggregate
preferred registers through generic mask operations slowed whole decodes by
roughly 10 to 25 percent; the retained `BlockU8x64` instead keeps four native
vectors intact through nibble lookup and mask extraction. Replacing the
builder's byte loop with `memchr`/`memcpy` runs also erased the one-pass gain on
these short strings. Neither losing implementation remains in the decoder.

The simdjson review also produced three measured tape variants. Draining the
preceding block after classifying the current one stayed inside noise. Emitting
scalar pseudo-structural starts slowed every large payload by roughly 10 to 14
percent because this fused consumer already carries its token cursor. Emitting
only string starts was inconsistent across two pairs and added a hybrid tape
contract. All three were removed: scheduling and tape choices that pay between
separate simdjson stages can duplicate work inside one fused parser.

Loading literal words and comparing them by XOR also failed to move the
geometric mean: generated code was already compact, short inputs improved about
three percent, and the numeric corpus lost about five. Mirroring builder depth
in a local scalar likewise measured slightly slower in its exact-parent pair.
Both variants were removed rather than retained as unproved complexity.

Two direct copies of simdjson's stage-two techniques initially lost. An
eight-digit SWAR probe inside the old source-level decimal loop cost 1.19x in
its first placement and remained about one percent slower when restricted to
one probe; short decimals did not amortize unconditional eligibility testing.
The later compiler lowering is different: it fuses the whole number token and
guards the word probe with the eighth byte, keeping the short-token path cheap.

The first 32-byte copy-and-find unescaper also lost 1.19x while every escape
already occupied a tape word. The retained design changes both halves: only a
closing quote is tagged, and the unescaper retains every backslash bit from a
16- or 32-byte copy rather than searching that copied window again. In a
seven-sample, 20 MB paired run this moved escaped throughput from about 0.569x
to 0.595x the colocated simdjson Lua binding, while the five-large-payload
geometric mean moved from about 0.750x to 0.767x. A lookup table for simple
escape dispatch then reduced the escaped ratio to 0.560x and was removed;
clang's branch layout remains faster for this corpus.

## Current comparison

The current twenty-five-sample, 5 MB paired run on Apple arm64/NEON and
simdjson 4.6.8 is committed at
`results/arm64-macos-neon-aot-optimized.json`. It puts Nupp at 0.679x
simdjson's Lua binding (95% bootstrap interval 0.678-0.683x) across the six
large payloads' geometric mean. Its exact-parent baseline remains at
`results/arm64-macos-neon-aot-baseline.json`: 0.650x (0.646-0.657x). The
intervals do not overlap, and the paired geometric mean improved 1.045x. The
current median throughput by payload was:

| payload | Nupp MB/s | simdjson Lua MB/s |
| --- | ---: | ---: |
| records | 326 | 438 |
| ASCII strings | 1,394 | 1,767 |
| Unicode strings | 1,571 | 2,014 |
| escaped strings | 690 | 1,428 |
| numbers | 447 | 729 |
| unique rejected keys | 655 | 900 |
| 30-byte object | 180 | 230 |

lua-cjson was unavailable to this run, so no current cjson claim is mixed into
these ratios; the harness will include it whenever it is present.

The subsequent fused number-token lowering was measured as an exact-parent
nine-sample, 2 MB pair. The numeric payload moved from 0.565x simdjson's Lua
binding (95% interval 0.552-0.584x) to 0.640x (0.616-0.648x), a 1.13x relative
gain. Absolute medians were 434 versus 767 MB/s in the parent and 446 versus
701 MB/s in the candidate; the ratio is the claim because the colocated
simdjson control exposes the machine drift between runs.

Temporary generated-C counter spans subsequently separated what remained in
that fused number operation. Each span read the same hardware counter, and an
adjacent empty read was subtracted before taking the median of fifteen fresh
processes. Each process decoded the ordinary 20,000-number corpus ten times.
Of the helper's measured work, grammar scanning was 51.5 percent, conversion
6.4 percent, and builder selection plus Lua publication 42.1 percent. None of
the 200,000 calls in a process used `strtod`. A second corpus made all 5,000
tokens ambiguous long decimals and decoded it ten times: grammar was 34.2
percent, conversion 60.1, and publication 5.7; `strtod` was 97.0 percent of
that conversion term. The counter code was removed after the measurement.

The apparent escaped-string regression was a harness boundary instead. The
942-954 MB/s figures came from 2 MB exact-parent experiments whose timed batch
did not collect. The later 690 MB/s result used 5 MB batches after one
collection shared by all eighteen implementations. Runner rotation therefore
rotated allocation debt as well as order. The historical fast decoder's own
retained 5 MB direct-fused result was already 696 MB/s, so there is no source
commit between those figures to blame.

On the current binary, stopping collection only for an isolated timed loop
gave 934 MB/s at both 2 MB and 5 MB; with collection enabled, changing only
the batch boundary produced 698 and 908 MB/s. After collecting before every
timed implementation, the fifteen-sample result committed at
`results/arm64-macos-neon-gc-isolated.json` measured escaped strings at 759
MB/s. The six-large-payload Nupp/simdjson geometric mean is 0.680x (95%
bootstrap interval 0.676-0.683x), essentially the previous 0.679x. This change
makes per-payload GC attribution repeatable; it does not claim a decoder gain.

The schema-driven record path has a separate 31-sample comparison because it
constructs nominal values rather than the benchmark's ordinary Lua tables. An
87-byte record took 781 ns through both a prepared Serde binding and the
underlying native builder, against 531 ns for the simdjson Lua binding.
The retained pre-change binary took 1,096 ns in prepared Serde against 536 ns
for simdjson: native-complete construction removed the second traversal and
improved prepared decode by 1.40x. Direct `string.buffer` input took 816 ns;
avoiding its copy is real, but layout validation costs more than copying this
particular 87-byte input.

The large-payload result is not an arithmetic average of those rates. Each
sample forms its colocated throughput ratio first; the report then takes the
geometric mean across payloads and bootstraps those paired means. An earlier
scale check on one 95.9 MiB records document reached 372.9 MB/s against
simdjson's 389.7 MB/s; it remains a useful GC calibration, not the current
throughput claim above.

The generated eager fused decoder is now 198,014 bytes of C. Five direct Apple
clang `-O3` compiles took 0.19-0.20 seconds and each produced a 36,072-byte
object. The recorded
production C++ boundary took 1.35 seconds and produced 198 KiB, while
simdjson's separate single-header implementation took another 0.58 seconds and
85 KiB. Those are compiler-only timings rather than complete build timings,
but the Nupp-generated decoder still compiles about six times faster and emits
about one sixth of the combined object bytes.

The earlier phase instrumentation is the one to read carefully. Interning is
`lua_pushlstring`, and simdjson's
binding calls the same function to build the same Lua strings, so that share is
shared and nothing here wins it back. Taking it out of the comparison is what
makes the rest legible: on ascii the whole decode is about 1.01 ms/MB against
simdjson's 0.62, roughly 0.38 of each is interning, and what remains is 0.63
against 0.24. The gap lives entirely in the other two thirds, split about
evenly between the scan and the traversal that walks the tape.

Set `NUPP_JSON_BENCH_OUTPUT` to write that JSON report without shell
redirection. The prior copied-tape Apple arm64/NEON result remains at
`results/arm64-macos-neon-fused.json`. The rooted-scratch result is committed at
`results/arm64-macos-neon-scratch.json`; it uses the same fifteen paired samples
and corpus hashes, so the two routes remain directly comparable. Across the five
large payloads the new route was 1.517x the since-removed tree builder (95% bootstrap CI
1.511–1.530x), 2.726x the old arena decoder (2.695–2.757x), and 5.797x the legacy
decoder (5.773–5.877x). The immutable result file retains every measurement
recorded by that version of the harness.

The historical dynamic-frame, reusable-byte-scratch, exact-capacity, and
integer-token result is committed at
`results/arm64-macos-neon-expansions.json`. On the same fifteen
sample/5 MB protocol it was 1.607x the since-removed tree builder (95% bootstrap CI
1.582–1.614x), 2.775x the arena decoder (2.739–2.816x), and 6.049x the legacy
decoder (6.024–6.076x). The immutable result file retains every per-payload
measurement from that run.

Those gains concentrated where presized objects or transformed strings
amortized their metadata; the retained per-payload figures make the small
regressions on plain string and decimal-heavy arrays explicit.

The same-machine simdjson calibration is committed at
`results/arm64-macos-simdjson-4.6.4.json`. It uses simdjson 4.6.4's `arm64`
implementation, four warmups, fifteen paired samples, reused parser buffers,
and input padding prepared outside the timed loop. Stage one reaches 3.550 GB/s
on records, 6.730 GB/s on ASCII strings, 4.476 GB/s on Unicode, 6.955 GB/s on
escaped strings, and 4.667 GB/s on numbers. The corresponding eager simdjson
DOM rates are 0.989, 3.891, 2.939, 1.804, and 0.803 GB/s.

Those DOM numbers construct simdjson's compact internal representation, not
Lua tables and strings, so they are a ceiling rather than an end-to-end API
comparison.

The end-to-end Lua binding result is committed at
`results/arm64-macos-neon-simdjson-lua.json`. It is a nine-sample, 2 MB-per-
sample run. Eager ordinary-Lua-DOM throughput is 276 MB/s on records, 995 MB/s
on ASCII strings, 1,119 MB/s on Unicode, 876 MB/s on escaped strings, and
478 MB/s on numbers. That is respectively 1.65x, 2.63x, 2.61x, 1.93x, and
1.85x the reference implementation recorded by that historical harness.

That historical result also records the now-removed lazy-DOM prototype. Its
numbers remain in the immutable result record, but the current harness replaces
them with On-Demand pull and serialization measurements.

The replacement result is committed at
`results/arm64-macos-neon-simdjson-pull-codec.json` with the same nine-sample,
2 MB-per-sample protocol. Full On-Demand materialization reaches 190 MB/s on
records, 943 MB/s on ASCII strings, 1,181 MB/s on Unicode, 676 MB/s on escaped
strings, and 499 MB/s on numbers. Pulling only `id` and `name` from each record
reaches 248 MB/s versus 227 MB/s for the colocated eager DOM-to-Lua path; the
advantage is selective allocation, not a promise that On-Demand is faster when
the requested shape is the whole document.

Serialization reaches 73, 308, 365, 293, and 66 MB/s on those five payloads.
The Lua table walk and per-string UTF-8 validation remain the main binding
costs; the immutable result file contains the complete historical comparison.

The lookup4/padded-load result is committed at
`results/arm64-macos-neon-stage1-lookup.json`. It is a nine-sample, 2 MB-per-
sample run and records the fused decoder separately from its public dispatch
alias. The fused path reaches 150 MB/s on records, 517 MB/s on ASCII strings,
586 MB/s on Unicode, 319 MB/s on escaped strings, and 170 MB/s on numbers.
Relative to the older fused result after normalizing each run to its colocated
reference measurement, the ratios improve on records, ASCII, Unicode, and
escaped strings; numbers are about eight percent lower. The large Unicode gain
is the intended removal of the comparison-heavy continuation path. Stage one
still trails simdjson because the fused parser processes one preferred vector
at a time instead of scheduling and draining 64-byte blocks ahead of stage two.

The prior tree result remains at `results/arm64-macos-neon-builder.json` as the
V4 baseline.

The J0 baseline is `results/arm64-macos-neon-baseline.json`; the structural
index result is `results/arm64-macos-neon-index.json`. Add separately named
native AVX2 results rather than replacing them. Cross-target C inspection checks
code generation but is not a performance run.
