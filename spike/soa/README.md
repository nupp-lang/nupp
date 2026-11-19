# Struct-of-arrays compiler storage on the native core: spike results (2026-11-19)

Branch `soa-spike` on origin (spike code under `spike/soa/`), based on
`579e7f582`, two commits behind `core-dev` `fd16c58a8`. It is based there
because the shared VM CLI generation `059f49b8` was built from that revision,
so guest builds ran without a VM CLI rebuild while the core fixpoint held the
machine. Measurements ran on a loaded M-series Mac (load average 10 to 17;
the core fixpoint was running). Prefer the instruction counts, which are
stable, to the wall times, which are not.

## Verdict

**Yes on memory, modest on speed, and not through `table.Array`.**

- **Memory is the real gain: 17 to 34 times less.** The parser module
  closure's CFGs are 1,762 graphs, 82,713 instructions, 26,741 blocks,
  144,567 block parameters and 32,768 edges. On the core they take +136 MB
  of RSS as tables and about 4 to 8 MB as columns. A six-field IR node costs
  459 B of RSS as a table or record (144 B live), 55 B as `{integer}` columns
  and 28 B as `{uint32}` columns.
- **Speed improves 1.3 to 1.5 times on today's core.** Columns cut a pass's
  instructions to 0.69 of the table version. A random-order walk of 1M nodes
  is 1.9 times cheaper in cycles. The interpreter is the ceiling: an empty
  numeric `for` iteration costs about 3,000 instructions, and each bytecode op
  about 300 to 800, so layout cannot be the main speed lever until handlers
  or a JIT shrink that.
- **`table.Array<T, "columnar">` cannot be used.** It does not compile for
  the core at all, and scalar `table.Array` spans run 10 times slower than
  plain Lua arrays there. Use packed or general Lua arrays (`{int32}`,
  `{integer}`) as the columns. They are on the pinned seed already.

## 1. Columnar access on the core

There is no columnar path on the core to lower to direct loads. Four separate
things block `table.Array<Inst, "columnar">` there:

1. `local struct Inst` is refused by the tagged profile
   (`src/nupp/compiler/vm/taggedprofile.nupp` `erasedStatement`, "only plain
   record declarations are admitted"). Only `cdef struct` is admitted.
2. `ffi` is nil in the core profile, so `ffi.typeof<Inst>()` is refused
   ("unresolved lexical or external value: dotIndex .typeof on nil ffi").
3. The implementation is LuaJIT FFI: `src/nupp/array/internal/storage.lua`
   does `require("ffi")` and mallocs through `ffi.C`, and `allocPacked` and
   `_allocateColumns` go through it. The core has no provider for it.
4. The tagged profile has no SoA lowering at all: `soaRow`, `soaField` and
   `soaFieldProjection` (set by `check/index.nupp`) appear in no `tagged*`
   module. On the VM, `rows[i].f` lowers in `vm/legacylower.nupp` (around
   lines 2384 to 2418 and 4096) to a method call `view:getField(i, ordinal)`
   or `setField`. That is `ColumnSpanImpl` in `src/nupp/mem/span.nupp` (around
   lines 891 to 990): a `% 1` bounds check, an ordinal check,
   `self.columns[ordinal]`, then an FFI cdata index.

What does run on the core, and how it runs:

- **Guest code is not machine code there.** The core compiles it to bytecode
  (`vm/corebytecode`), which the Nupp-written handlers in
  `runtime/core/guesthandlers.nupp` interpret, and s0 compiles those handlers.
  So on the core a "direct load" means a bytecode op that loads a typed
  element without a call or an allocation. Packed `{int32}` and `{integer}`
  Lua arrays already have that: `GetIdx` goes to the table's packed part.
- **A `cdef struct` field read allocates a view per access.**
  `vm/taggedstructs.nupp` `load` emits `LibCall STORAGE_VIEW` plus
  `GetIdx(view, 0)`, so a walk reading two fields costs 9,700 instructions
  per row, against 5,700 for a table.
- **A `table.Array.scalar` span index is a guest method call.**
  `vm/indexedaccess.nupp` issues `view:get(i)` or `view:set(i, v)` into
  `SpanImpl`, which costs about 2.4 µs per read: ten times a Lua array
  element.

**Estimate for a real columnar lowering on the core** (not prototyped,
because it is not small or contained): a core storage provider for
`Array.alloc`, admitting `local struct` with a core ctype witness in place of
`ffi.typeof`, and a tagged lowering of `soaRow`, `soaField` and
`soaFieldProjection` to a bounds check plus `GetIdx(column storage,
offset + i - 1)`. That is roughly 300 to 500 lines across the compiler and
the library, plus guest cases. It would end up no faster than a `{int32}`
column, which reaches the same `GetIdx`-on-packed-storage path today.

## 2. Memory per node and access speed (1M nodes, core)

The walk is `if insts[i].kind == 3 then sum += insts[i].a`. RSS is per row
over a 5.8 MB baseline. "Live" is `collectgarbage("count")` after a full
collect, which does not count table array parts.

| Representation | RSS B/row | Live B/row | Build ns/row | Walk ns/row | Walk instructions/row |
| --- | ---: | ---: | ---: | ---: | ---: |
| Hash tables `{kind=..,...}` | 459 | 144 | 3,618 | 381 | 5,714 |
| Records | 459 | 144 | 4,056 | 375 | 5,707 |
| `cdef struct` per row in `{Inst}` | 256 | 32 | 3,379 | 637 | 9,693 |
| `{integer}` columns ×6 | 55 | n/a | 1,391 | 240 | 3,627 |
| `{uint32}` columns ×6 (packed) | 28 | n/a | 5,313 | 264 | 3,975 |
| `table.Array.scalar(uint32)` ×5 (spans) | 20 | n/a | 16,256 | 2,411 | n/a |
| Hand-packed array of structures in one `Array<uint32>` | 20 | n/a | 15,519 | 2,823 | n/a |
| `table.Array<Inst, "columnar">` | does not compile on the core | | | | |

Order of access matters for tables and much less for columns:

| Walk, 1M rows | In order (cycles/row) | Shuffled (cycles/row) | IPC, in order then shuffled |
| --- | ---: | ---: | --- |
| Tables | 1,008 | 2,244 | 5.6 → 2.9 |
| `{integer}` columns | 667 | 1,175 | 5.4 → 3.8 |

- **In allocation order the core is compute-bound**, at an IPC of about 5.5.
  Shuffled, the table walk spends about 1,200 extra cycles a row on misses.
  That matches what the self-build reports when it walks cold memory.
- **Building a table node costs about 64,000 instructions**, against 18,800
  for six `{integer}` column appends. That is NewTable, SetIdx per field and
  growth.
- **Each table node uses about three times its live size in RSS** (459 B
  against 144 B), separately worth investigating.

### Per-op costs on the core

Instructions per iteration, beyond the about 3,050 a bare `for i` iteration
costs:

| Op | Extra instructions |
| --- | ---: |
| `+` | +555 |
| Packed store | +1,690 |
| General store | +1,400 |
| `math.abs` (LibCall) | +2,800 |
| Guest call | +4,600 |
| `math.i32.wrap` (LibCall) | +13,900 |

The loop body is about ten bytecode ops (`logs/soa-loop.graphs`): `Add`,
`Lt`, `Le`, two branches, and a jump that carries every live value as block
arguments.

## 3. A real pass: graphprune's used-value walk, CHK dominators, an operand walk

The input is `parser.graphs`: every closed-block graph the core's tagged
profile built for `nupp.compiler.syntax.parser`'s 106-module closure, dumped
by `spike/dumpgraphs.lua`. The table version is `graph.nupp`'s own shape: a
table per block, per instruction's operand list and per edge. The column
version is module-wide columns with index ranges, and its scratch is sized
once and stamped per graph, not cleared. Checksums match across all variants
and both runtimes.

| Core, parser closure | RSS over baseline | Build | Operands | Prune | Dominators | Instructions/rep (3 passes) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Tables | +136 MB | 517 ms | 43 ms | 549 ms | 176 ms | 13.97 G |
| `{integer}` columns | +4 MB (8 MB computed) | 402 ms | 33 ms | 359 ms | 118 ms | 9.70 G (0.69×) |
| `{int32}` columns | +3 MB (4 MB computed) | 1,434 ms | 33 ms | 1,137 ms | 354 ms | 27.55 G (1.97×) |
| Arena of `table.Array<int32>` (double plus `copyfrom`; instruction columns only) | n/a | 2,451 ms | 325 ms | n/a | n/a | n/a |

- **`{int32}` loses only to the wrap.** Every store into a `{int32}` column
  needs `math.i32.wrap`, a 14,000-instruction LibCall on the core, even when
  copying from another `{int32}` column.
- **The arena wrapper loses to the span call.** It pays a guest method call
  per element.

VM reference, same input, from the timing logs: tables 648, 124, 912 and
298 ms; `{integer}` columns 776, 124, 936 and 311 ms. On the VM the layouts
tie. The VM's RSS is dominated by the in-process compiler, so it is not
reported.

## 4. Ergonomic friction

- **No zero-cost distinct index types.** `types.range` aliases are not brands,
  so an `InstId` passes where a `TypeId` is wanted, and a phantom
  `type Id<T> = integer` erases (`spike/ergo.nupp`). Records allocate, and a
  `cdef struct` allocates storage on the core, so it is no newtype. A
  `distinct`/newtype integer needs a language feature, and stage zero then
  delays compiler use by one release after it lands.
- **Affine columnar arrays cannot grow in place inside a record.** Replacing
  `arena.insts` through an `exclusive` parameter is NUPP2602/NUPP2603.
  Growth works by `takes` plus returning the new owner into a local. A
  compiler `Function` record whose methods push into columns therefore wants
  managed arrays (`Array.scalar`) or plain Lua arrays, not
  `alloc(..., "columnar")`.
- **`{int32}` columns need `math.i32.wrap` on every store**, including a copy
  from another `{int32}` column: loads from Lua arrays are not "established",
  so the code is noisy, and on the core each wrap is a slow LibCall.
- **`{uint8}`/`{uint16}` arrays are refused** (NUPP2012, storage-only names),
  so `kind` and `flags` byte columns need `table.Array.uint8`, which is the
  slow span path on the core.
- **Index arithmetic needs `: integer` annotations.** `local count = 0;
  count = count + 1; t[count]` is NUPP2004, because the arithmetic widens to
  `number`, so every index counter has to be annotated.
- **Stage zero blocks nothing for plain `{integer}` or `{int32}` columns**:
  the pin already has them. A columnar `table.Array` path or a distinct id
  type would reach `src/` only one release after it lands.

## Recommendation and order

1. **Flatten the CFG first** (`vm/graph.nupp` and its passes). It is already
   column-per-block (`op`, `dst`, `args`, `pos`, `cert`); move to
   function-wide or module-wide `{integer}` columns, with operand, parameter
   and edge-argument pools addressed by ranges. Block parameters outnumber
   instructions 1.75 to 1, and the passes are index loops already.
2. **Weigh compact records on the core (runtime Decision 16) against
   rewriting the tree representations.** Today a record is a hash table with
   no presizing (NewTable, then a SetIdx per field, then SETMETATABLE), at 459
   B of RSS for six fields. Fixed slots would win back most of the memory for
   every structure the compiler has without changing its code, where SoA has
   to be done structure by structure.
3. **CST nodes after that, and types last.** Types are identity-heavy and
   exposed to comptime as values, so they are the hardest to move.
4. **Speed comes from the core interpreter, not layout:** per-op handler
   overhead (`charge`, `current`, `branch` and `dispatch` on every op),
   LibCall cost (3,000 to 14,000 instructions), and table allocation (64,000
   instructions per six-field node). Columns are 1.3 to 1.5 times faster;
   those levers are 10 times.
5. **Make `{int32}` loads established, or `i32.wrap` cheap on the core**,
   before preferring `{int32}` over `{integer}`. That halves column memory
   again.

## Found along the way

- **VM miscompile:** `sum + rows[i].a`, with `sum: number` and `a` a `uint32`
  field read through a packed `table.Array` row view, wraps modulo 2^32
  (`spike/wrapbug.nupp` prints 3489660928 against 12079595520). The core
  does not compile this program at all.

## Layout

- `spike/`: `access.nupp` (variants by `SOA_WHICH`, plus `SOA_OP` per-op
  costs), `pass.template.nupp.in` with `columnar.part.nupp.in` and `gen.sh`, which
  generate `pass.nupp` (then `nupp fmt --write`), `dumpgraphs.lua`, `ergo.nupp` and `wrapbug.nupp`.
- `bundles/`: core bundles. Run one as
  `build/c-core-bridge/nupp-core BUNDLE empty.bin out.bin` with `SOA_*`
  set; `SOA_GRAPHS` names `parser.graphs`.
- `logs/`: raw outputs.
- **How to rebuild a bundle:** in a checkout at `579e7f582` with that VM CLI
  generation, copy the program over `bench/vm/workloads.bench.nupp` and run
  `tests/core/guests/run.lua benchworkloads` with `NUPP_GUEST_QUICK=1
  NUPP_GUEST_MODES=normal NUPP_GUEST_STRESS=0 NUPP_GUEST_SHARDS=1`. The
  bundle lands at `build/core-guests/benchworkloads-normal.bundle`. A new case
  name does not work, because `nupp.core.guestbuild` comes from the CLI image
  rather than from source.
