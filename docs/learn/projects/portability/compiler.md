---
order: 580
---

# Browser compiler bundle

The playground runs the Nupp compiler under LuaJIT in a retained v86 guest.
Build the compiler image with:

```bash
scripts/prelude-image luajit
```

The output lives in `build/browser-luajit`. It supplies native storage and
inline C declaration/layout support for the i686 Linux guest. It cannot read
host headers, invoke a C preprocessor, resolve an arbitrary project, or perform
AOT compilation.

The default playground loads verified, compressed LuaJIT bytecode and a
pre-LuaJIT VM snapshot in a dedicated Worker. One retained compiler session
handles edits and hover queries. Stop terminates a busy VM; subsequent work
creates a fresh one. Application execution uses a separate guest.

The asset manifest records compiler and runtime sizes, digests, matching source
archives, and the pinned guest identity. Snapshots restore fresh entropy and
wall time; invalid snapshots fall back to normal boot of the same guest. See
the [LuaJIT browser host](../../performance/ahead-of-time/wasm.md).

## Source compatibility

The browser compiler emits LuaJIT source. A request may set
`compat = "lua51"` to enforce the checked stock-Lua source subset; this rejects
unsupported syntax and runtime dependencies rather than invoking another
lowerer. See [portable libraries](libraries.md).

## Limits

An in-memory browser request accepts one source file. It does not read imported
application files, run comptime worker processes, render documentation, import
C headers, or compile AOT artifacts. The bundle contains the standard-library
declarations needed while checking source.

::: seealso
- [Build source sets](../build.md#target-source-sets)
- [Portable Lua libraries](libraries.md)
:::
