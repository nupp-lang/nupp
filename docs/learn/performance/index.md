---
order: 600
---

# Performance

A Nupp program runs on the Nupp VM. The compiler lowers checked source to VM
bytecode, and the types it proved choose the instructions: a value the checker
knows is a `number` or an integer is kept unboxed in a typed register, while
one it does not know stays a tagged value the instruction has to inspect.

`nupp bc` prints the bytecode a file lowers to, beside the source line each
instruction came from:

```bash
nupp bc src/sum.nupp
```

For this loop over a `{number}`:

```nupp
local function sum(values: {number}): number
    local total = 0.0
    for i = 1, #values do
        total = total + values[i]
    end
    return total
end

print(sum({1.0, 2.0, 3.0}))
```

the listing shows float-register instructions, `GetIdxF` reading an element
and `FAdd` accumulating it, rather than generic table reads and additions:

```text
  4 |         total = total + values[i]            | 0007 GetIdxF 3 1 0
    |                                              | 0008 Add 2 2 3
    |                                              | 0009 FAdd 0 0 3
```

That answers what an annotation cost, or bought, the same way on every machine
and with no warm-up. `nupp bc --json` returns the same listing by function.

## Optimization passes

There are none. The optimizer rewrote the Lua the compiler used to generate,
and went with it. `-O0`, `-O1` and `-O2`, `--remarks`, `--remarks-for`,
`--remarks-out` and `-Zno-opt` are still accepted and change nothing, and no
`OPT` remark is reported.

## Measuring

Read the bytecode to see what a construct lowers to, and measure to see what it
costs:

- [Benchmarks](benchmarks.md) runs each case in its own process, replicates
  across processes, and says when a difference is not yet a difference.
- [Ahead-of-time compilation](ahead-of-time/index.md) covers `@aot` and vector
  code through `nupp.simd`.

::: seealso
- [Benchmarks](benchmarks.md): measure changes and compare builds.
- [Native runtime](../../reference/native-runtime.md) for what executes a program.
:::
