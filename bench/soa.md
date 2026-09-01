# SoA lowering benchmark

Run the source benchmark from the repository root:

```sh
./bin/nupp run -O1 bench/soa.nupp
./bin/nupp build -O1 bench/soa.nupp
LUA_PATH='src/?.lua;src/?/init.lua;;' luajit -joff bench/soa.lua
```

It compares the compiler-lowered `rows[i].field` spelling with four hand-written
single-field cdata arrays and the canonical AoS struct. The timed update consumes two
of four fields, over 100,000 rows and 30 steps. Allocation and initialization are
outside the timed region; a checksum after the timer observes every updated `x` and
`y`, so allocation sinking or dead-store elimination cannot erase the timed kernel.
The first complete round is warmup and five medians remain.

One representative Apple ARM64 run measured:

| mode | Generated SoA | Hand SoA | AoS | Generated / hand |
| --- | ---: | ---: | ---: | ---: |
| LuaJIT traced | 1.77 ms | 1.78 ms | 1.77 ms | 0.993x |
| LuaJIT interpreter | 274.63 ms | 566.18 ms | 502.86 ms | 0.485x |

The traced result is within the plan's ten-percent gate. The canonical
`for i = 1, #rows` form proves the row range once and emits direct numeric column
loads/stores with the slice offset; arbitrary indexes retain `checkedIndex`. Inspecting
the generated Lua and `nupp bc --check` is part of the gate so a future change cannot
quietly replace the direct form with a proxy, closure, reflective lookup, or helper
call. Interpreter numbers favor the generated representation partly because the hand
baseline uses one-field structs to express raw primitive arrays through checked Nupp;
the traced comparison is the representation decision this benchmark is intended to
guard.
