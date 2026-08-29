# macOS arm64 baseline

Revision: `9d43d4063f9c4a08a59249e3697430ded3b8f548`

Machine: Apple M1 Mac mini, 8 cores, 16 GB memory, Darwin 24.3.0. Each
number below is the median reported by one nine-sample benchmark process.
The summary is the median of three processes.

| Measurement | Run 1 | Run 2 | Run 3 | Baseline |
| --- | ---: | ---: | ---: | ---: |
| Cold scheduler | 0.07 ms | 0.10 ms | 0.09 ms | 0.09 ms |
| Scalar round-trip | 14.35 us/op | 14.46 us/op | 12.95 us/op | 14.35 us/op |
| Text, 4 KiB | 312.58 MiB/s | 327.71 MiB/s | 362.19 MiB/s | 327.71 MiB/s |
| Record, 4 KiB | 265.04 MiB/s | 288.11 MiB/s | 291.84 MiB/s | 288.11 MiB/s |
| CPU serial | 303.07 ms | 306.63 ms | 303.78 ms | 303.78 ms |
| CPU parallel | 74.38 ms | 72.97 ms | 73.60 ms | 73.60 ms |
| CPU speedup | 4.07x | 4.20x | 4.13x | 4.13x |

## Optimization ladder

The same machine and benchmark were used after each isolated change. Rows are
the median of three benchmark processes, each of which reports nine-sample
medians. The codec-reuse row is the one quiet accepted process because a
concurrent full test run began before its repeats; later rows retain that change.

| Revision | Change | Scalar | Text, 4 KiB | Record, 4 KiB |
| --- | --- | ---: | ---: | ---: |
| `9d43d406` | Baseline | 14.35 us/op | 327.71 MiB/s | 288.11 MiB/s |
| `9fe92878` | Reused codecs and zero-copy decoder input | 12.64 us/op | 408.53 MiB/s | 370.38 MiB/s |
| `a0489ced` | Split control envelopes from payload bytes | 12.75 us/op | 607.19 MiB/s | 463.01 MiB/s |
| `19517c28` | Reused validation discovery order | 11.17 us/op | 629.19 MiB/s | 563.67 MiB/s |
| `fa1bad0f` | Avoided eager validation allocations | 10.25 us/op | 703.62 MiB/s | 592.01 MiB/s |
| `dee4701a` | Bypassed serialization for primitive values | 10.25 us/op | 758.00 MiB/s | 593.66 MiB/s |

The final result cuts scalar round-trip latency by 29%, raises plain 4 KiB
throughput by 2.31x, and raises 4 KiB record throughput by 2.06x. CPU-parallel
speedup remains workload- and machine-scheduling-bound: the final three-process
median was 4.22x versus the 4.13x baseline, with no change to the CPU job itself.

## Native predefined frames

A later pass started at `daa4c465`, after the optimization ladder above and
subsequent worker work had landed. Number and string task/reply frames now stay
native in the C channel. Dynamically shaped values still use the `string.buffer`
codec. Each number below is again the median of three benchmark processes, with
nine measured samples per process.

| Measurement | Before | Native frames | Change |
| --- | ---: | ---: | ---: |
| Scalar round-trip | 9.58 us/op | 8.67 us/op | 9.5% less latency |
| Text, 4 KiB | 10.19 us/op | 9.02 us/op | 11.5% less latency |
| Text, 4 KiB | 766.68 MiB/s | 866.13 MiB/s | 13.0% more throughput |
| Record, 4 KiB | 13.80 us/op | 13.25 us/op | dynamic fallback control |

Two follow-on ideas failed the benchmark gate and were removed. Interning
callable IDs per lane regressed scalar and text latency to 9.50 and 10.05 us/op.
Bypassing the generic worker-side frame and packed-value helpers measured 8.92
and 9.06 us/op, which was neutral for text and 2.9% slower for scalars. The
remaining work in those paths is cheap enough under LuaJIT that the added
bookkeeping costs more than it saves.

## Compiler-prepared primitive transfers

The compiler now publishes transfer plans for exported one-argument functions
whose checked parameter and result are numbers or strings. The runtime uses the
plan to find the callable without scanning loaded modules, skips the redundant
graph-validation walk, and emits the predefined native frame without temporary
wire or frame tables. `any`, records, multi-value signatures, captures, and
other uncertain shapes retain the checked dynamic path.

| Measurement | Native frames | Prepared transfer | Change |
| --- | ---: | ---: | ---: |
| Scalar round-trip | 8.67 us/op | 6.16 us/op | 29.0% less latency |
| Text, 4 KiB | 9.02 us/op | 5.82 us/op | 35.5% less latency |
| Text, 4 KiB | 866.13 MiB/s | 1342.35 MiB/s | 55.0% more throughput |
| Record, 4 KiB | 13.25 us/op | 12.63 us/op | dynamic fallback control |

The retained result is the median of three benchmark processes. Their scalar
medians were 6.83, 6.16, and 6.04 us/op; text medians were 5.79, 5.84, and 5.82
us/op. On the same machine the raw Love2D channel benchmark measured 5.01 us/op
for a scalar and 5.75 us/op for 4 KiB text. The public Nupp text task is now
within 1.2% of that raw channel echo; the structured scalar task remains 23%
slower.

Two transport follow-ups were rejected. Recycling one message allocation under
the channel lock regressed scalar and text latency to 9.72 and 9.81 us/op.
Returning native task tuples directly into a larger Lua scheduler loop regressed
them to 8.35 and 16.38 us/op because the loop lost its favorable LuaJIT trace
shape. Both experiments were removed.

## Schema-tagged record transfers

After application task scopes landed, the benchmark gained a same-process
dynamic control: the identical `Payload` record crosses through an `any` to
`any` function, forcing the checked `string.buffer` fallback. The compiler now
publishes ordered layouts for exact records whose stored fields are numbers,
strings, or booleans. C assigns each layout fingerprint a short channel-local
ID on first use, walks the fields, and rebuilds the table before Lua restores
the destination state's metatable.

| Measurement | Run 1 | Run 2 | Run 3 | Median |
| --- | ---: | ---: | ---: | ---: |
| Prepared record | 13.10 us/op | 18.08 us/op | 12.82 us/op | 13.10 us/op |
| Dynamic record | 21.12 us/op | 19.99 us/op | 18.22 us/op | 19.99 us/op |
| Prepared throughput | 596.37 MiB/s | 432.11 MiB/s | 609.40 MiB/s | 596.37 MiB/s |
| Dynamic throughput | 369.85 MiB/s | 390.89 MiB/s | 428.71 MiB/s | 390.89 MiB/s |

The schema lane cuts the controlled record latency by 34.5% and raises
throughput by 52.6%. A runtime metatable or field-kind mismatch returns to the
dynamic validation and codec path; the integration test mutates a typed record
through `any` and verifies that fallback in both directions.

A full preallocated 1024-slot channel ring was rejected. Advancing across the
whole bounded metadata array destroyed cache locality and increased cold start;
the existing allocator instead reuses a very small hot working set. The retained
channel therefore keeps its linked queue and schema IDs, and allocates typed
field storage only on record messages.

## Restored blocking awaits and cached record metatables

Re-measuring the whole table on the same machine showed that the
application task scope work had quietly regressed every public path: it
replaced the direct blocking wait with the suspension subscription path
unconditionally, and made `isDone` sweep every lane's channel and native
task state per call. Scalars measured 9.7 us and 4 KiB text 10.3 us at
`c48e66f9`, not the 6.16 and 5.82 us retained above, which had been
recorded before the scope work landed and were never rerun for
primitives. The prepared record's 13.10 us therefore stacked roughly
4 us of regression on top of its own extra work.

Two changes were landed after bisecting. `04c1a78b` blocks an ordinary
await on the one channel its reply must arrive on and drains only the
task's own lane in `isDone`; a handled extent still subscribes and polls
the whole scheduler. `56d304fe` resolves a native record frame's
metatable address once per Lua state instead of walking `require` and a
pattern match on every receive, which also keeps `string.gmatch` out of
the traced pop path.

| Measurement | At `c48e66f9` | Run 1 | Run 2 | Run 3 | Median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Scalar round-trip | 9.88 us/op | 5.48 us/op | 5.41 us/op | 5.47 us/op | 5.47 us/op |
| Text, 4 KiB | 10.64 us/op | 6.22 us/op | 6.38 us/op | 6.08 us/op | 6.22 us/op |
| Record, 4 KiB | 12.54 us/op | 6.81 us/op | 7.00 us/op | 7.09 us/op | 7.00 us/op |
| Record throughput | 623.01 MiB/s | 1147.21 MiB/s | 1116.60 MiB/s | 1102.42 MiB/s | 1116.60 MiB/s |
| Dynamic record | 17.46 us/op | 14.59 us/op | 14.13 us/op | 12.53 us/op | 14.13 us/op |

The prepared 4 KiB record round trip now sits within 0.8 us of the same
payload sent as a bare string, the target the schema work aimed at. The
remaining record-specific cost is the per-push schema descriptor
marshalling and keyed registry search, the per-field name interning, and
the reply-side guards; completing the cached schema-ID call path would
attack those, but they are now sub-microsecond in total.

## Bounded adaptive spin before channel sleeps

With the public layer repaired, the dominant remaining cost was the
operating system itself: two condition-variable sleep and wake cycles
per round trip. `2f214fdb` polls the queue head for a bounded window
before sleeping and skips the wake syscall when no reader is asleep. A
per-channel credit makes the spin adaptive, because both fixed variants
lost: an always-on 8000-poll window regressed the dynamic record path
from 14.1 to 20.5 us, and a 1000-poll window expired just before typical
prepared replies arrive and regressed every prepared path by about 3 us.

| Measurement | Before | Run 1 | Run 2 | Run 3 | Median |
| --- | ---: | ---: | ---: | ---: | ---: |
| Scalar round-trip | 5.47 us/op | 3.42 us/op | 2.35 us/op | 2.25 us/op | 2.35 us/op |
| Text, 4 KiB | 6.22 us/op | 3.63 us/op | 3.37 us/op | 3.06 us/op | 3.37 us/op |
| Record, 4 KiB | 7.00 us/op | 4.00 us/op | 3.79 us/op | 3.67 us/op | 3.79 us/op |
| Record throughput | 1116.60 MiB/s | 1951.50 MiB/s | 2061.35 MiB/s | 2130.68 MiB/s | 2061.35 MiB/s |
| Dynamic record | 14.13 us/op | 10.28 us/op | 12.74 us/op | 13.65 us/op | 12.74 us/op |

The eight-lane CPU speedup stayed at 5.0x, and the spin only runs on
entry to a blocking pop, so idle lanes sleep as before.

## Dart comparison

`bench/workers/dart/echo_bench.dart` mirrors the warm sequential
benchmark shape against one persistent isolate on Dart 3.13.1, same
machine, median of three processes:

| Payload | Dart isolate echo | Nupp public task |
| --- | ---: | ---: |
| Scalar | 2.92 us/op | 2.35 us/op |
| Text, 4 KiB | 3.08 us/op | 3.37 us/op |
| Record, 4 KiB | 2.86 us/op | 3.79 us/op |

Dart's latency is flat across payloads because isolates in one group
share immutable strings instead of copying them. The Nupp scalar task
is now faster than the Dart echo, text is within 10%, and the prepared
record trails by about 0.9 us: the per-push schema descriptor
marshalling, keyed registry search, and reply-side guards described
above, which the cached schema-ID call path would remove.

## Cached schema ids and record detection under any

`d1c9151a` completes the registered-schema design: a schema crosses
into C once per channel and every later push carries only the short
native id, instead of re-marshalling the fingerprint, address, and
field tables into a locked keyed search twice per round trip. Exported
records with all-primitive stored fields also publish their layout
keyed by the record table itself, so a value that is exactly such a
record takes the native path even under an `any` signature; a stored
key count that differs from the declared fields returns to the dynamic
copy, which preserves extra keys. `905bb353` separately stopped the
descriptor-less spawn path from rescanning every loaded module per
call, which was most of the dynamic fallback's cost.

The benchmark's dynamic control now sends a plain table, since the
former control payload, an exact record through `any`, is precisely
what detection promotes. Medians of three processes:

| Measurement | Before | Median | Change |
| --- | ---: | ---: | ---: |
| Scalar round-trip | 2.35 us/op | 2.50 us/op | unchanged |
| Text, 4 KiB | 3.37 us/op | 3.20 us/op | unchanged |
| Record, 4 KiB | 3.79 us/op | 3.84 us/op | matches text |
| Record through `any` | 12.74 us/op | 4.17 us/op | 67% less latency |
| Plain table fallback | - | 6.88 us/op | new control |

Prepared records now cost the same as the equivalent string payload,
which was the schema work's stated target, and the record through
`any` sits within 0.4 us of the prepared path. Against the Dart
harness on the same machine, every Nupp record shape is now within
1.3 us of the 2.86 us isolate echo, with scalars still faster.

## Native envelope and channel dictionary for the fallback

The buffer-only spike (preserved unmerged on `spike-buffer-only`)
established that one serializer path cannot replace the specialized
frames, but two of its pieces compose with them. The dynamic fallback's
control header is no longer `buffer.encode`d and decoded per message:
id, module, member, and value count ride a native buffer frame beside
the payload bytes. Record addresses register once in a channel-scoped
append-only dictionary instead of travelling as a list on every
message, and each state keeps one codec per channel, rebuilt only when
the dictionary grows. The validation walk and its semantics are
unchanged: the spike showed the serializer silently strips unlisted
metatables and duplicates shared subtables, so the walk stays wherever
shapes are not compiler- or registry-proven.

Medians of three processes:

| Measurement | Before | Median |
| --- | ---: | ---: |
| Scalar round-trip | 2.50 us/op | 3.34 us/op (noise) |
| Text, 4 KiB | 3.20 us/op | 3.60 us/op (noise) |
| Record, 4 KiB | 3.84 us/op | 3.54 us/op |
| Record through `any` | 4.17 us/op | 3.91 us/op |
| Plain table fallback | 6.88 us/op | 5.16 us/op |

The fallback improved 25%; the prepared rows moved within the session's
noise band. The spike's other finding is recorded for future work: a
`pcall` around the serializer's decode fast function segfaults in
libunwind on macOS arm64, so the receiver detects dictionary growth by
count instead of retrying a failed decode.

## Optional fields in record schemas

An optional stored field is a two-member union with nil. It previously
disqualified its whole record from the native schema path; it now
travels as its primitive kind plus a presence mark. The native walk
clears the mark for an absent value and the receiver skips the key, so
nil and present values round-trip exactly, and the key-count guard
balances against present fields, keeping extra-key mutations on the
validated fallback.

Medians of three processes: a 4 KiB record with an absent optional
string measures 3.67 us, the same as the all-required record, where the
shape previously took the 5.2 us codec fallback.

## Shared immutable byte regions

NEP 22's core landed: `nupp.mem.sharedbytes.Region`, an engine-owned
immutable byte extent that crosses lanes as a message attachment while
the copied spine carries a placeholder, is sliced without copying, and
is read in place through the existing `nupp.mem.span` byte view. The
benchmark's region carries the same 1 MiB payload as the text row and
its worker counts newlines through a view; correctness assertions cover
slice reads, extent equality, and a cross-lane count, and the worker
bundle test round-trips a slice.

Medians of three processes at the benchmark's usual `-O0`:

| Measurement | Text | Region | Change |
| --- | ---: | ---: | ---: |
| 1 MiB round trip | 101.14 us/op | 4.51 us/op | 22x less latency |
| 1 MiB scan in the worker | 827.70 us/op | 1209.93 us/op | see below |

At `-O0` span indexing stays behind its metamethod, so scanning through
a view trails scanning a copied string. One `-O1` process, where a
nonescaping view is virtualized into direct loads, measured the region
scan at 695.77 us against the text scan's 828.60: faster than the
string loop while also skipping the string's 100 us copy. The crossing
win does not depend on the optimizer; the in-place read win does.

## Deliverable targets optimize by default

Binary, bundle, and component targets now build at `-O2` unless their
manifest entry declares its own `optimize` level, an explicit `-O`
still wins, and the compiler builds itself optimized through
`optimize = 2` on its own target. The change surfaced two latent
faults: the CLI collapsed an absent `-O` into an explicit level 0, so
half of the fixpoint pipeline built optimized and half did not until
absence became representable; and the tracked stage-0 bundle had to be
refreshed to read the new manifest key.

This retires the previous section's caveat: the retained benchmark's
binary target now builds optimized, so the in-place scan row measures
what shipped code sees. Transport rows are insensitive to the level,
because the staged runtime was already fixed at the compiler's own
level. Medians of three processes at the new basis: the region scan
measures 703.77 us against the copied-string scan's 839.23, and the
1 MiB region crossing holds at 4.51 us against 101.78 as a string.
The full suite, the doctest corpus, and a byte-identical fixpoint all
pass at the new default; the two scintillua doctest failures that
predated this work stopped reproducing under the optimized compiler.

## Transferable owned buffers

NEP 23 landed: a worker parameter may take a `nupp.mem.heap` array of a
fixed-width element and an affine result may return one, and neither is a
copy. The message carries the allocation's pointer as a moved attachment,
the receiving lane becomes the one owner, and the affine layer consumes
the sender's binding at the spawn, so use after transfer is a compile
error at the send site. A message destroyed unread frees its moved
allocations exactly once, whether by cancellation, queue teardown, or a
discarded result, and the benchmark's ping-pong holds peak RSS flat at
63 MiB across 330 crossings of one 8 MiB buffer.

Medians of three processes:

| Measurement | Copied string | Moved buffer | Change |
| --- | ---: | ---: | ---: |
| 8 MiB there and back | 869.53 us/op | 8.43 us/op | 103x less latency |
| 4 KiB there and back | 3.41 us/op | 7.78 us/op | the copy wins |

The move's cost does not grow with the payload: 4 KiB and 8 MiB cost the
same 8 us, which is the attachment round trip itself, twice the region
row's one-way crossing because both directions carry an attachment. Below
tens of kilobytes the string fast path is still quicker, the same
guidance regions carry: moves are for large mutable working sets. The
worker bundle test round-trips a stamped uint8 buffer and moves an int32
buffer one way for a lane-side sum and free, covering two layout tags.

## Builder reservations and region accounting

The two blocking NEP 22 specification gaps landed. A builder lends a
checked `span.Writable<uint8>` over reserved storage through a
reserve-and-commit pair: growth is confined to the reserve, every other
builder operation is a compile error while the writer lives, and misuse
answers loudly, whether a second reserve, a freeze or append with one
open, or an overcommit. External bytes are charged per state with the
block as the unit of account, once however many handles and slices name
it, and charges pay collector step debt exactly as the state's own heap
allocation does, vanishing when its last handle is collected.

The region benchmark rows are unchanged under accounting: the 1 MiB
crossing measures 4.83 us against the 4.87 baseline. The bundle test
asserts the reserve-commit-append-freeze cycle's content, that a charge
appears once per block, and that collection discharges it.
