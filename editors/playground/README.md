# Nupp Playground

An in-browser editor that checks and compiles Nupp with the real, self-hosted
compiler — not a reimplementation, not a server round-trip. `bootstrap/nupp.lua`
runs client-side in a [fengari](https://fengari.io) (pure-JS Lua 5.3) VM
inside a Web Worker, off the main thread.

## Why fengari, not LuaJIT-in-WASM

Nupp's compiler is self-hosted: `bin/nupp` runs `bootstrap/nupp.lua` under
LuaJIT until the project's own `build/` compiler exists, and both are plain
Lua text — no C toolchain in the loop. That portability is what makes running
it in a browser tractable at all: point a Lua VM at that file instead of
porting the compiler to JavaScript.

The remaining obstacle is that LuaJIT itself doesn't reduce to portable C —
its interpreter is hand-written assembly per target architecture, so there is
no "LuaJIT.wasm" to compile. `bootstrap/nupp.lua` also isn't quite portable
Lua as shipped: it uses a few LuaJIT-only pieces, listed below with what
stands in for each. See [`src/host-runtime.lua`](src/host-runtime.lua) for
the implementations and the exact reasoning at each one, and
[`src/worker.js`](src/worker.js) for how it's wired to `bootstrap/nupp.lua`.

 Piece               Where it's used                        Stand-in
 ───────────────────  ──────────────────────────────────────  ─────────────────────────────
 `const NAME = value` nupp.build.hash's own top-level locals   rewritten to `local`, at build time
 `0x..ULL` literals    nupp.build.hash (content-hash cache)    stripped to plain Lua 5.3 ints, at build time
 `bit.*`               nupp.cdecl (C-declaration decoding)     real bitwise ops, Lua 5.3 native
 `string.buffer`       nupp.build.store (project-index cache)  a plain string-accumulator
 `cjson`               build cache, `--json`-shaped output     a small JSON codec
 `ffi`                 nupp.cdecl, nupp.check.ffi              stub — see below
 disk I/O              manifest/config lookup, project cache   `io.open`/`io.popen` return "not found"

The first two rows are fixed at *build* time, by
[`tools/patch-bootstrap-for-browser.lua`](tools/patch-bootstrap-for-browser.lua)
— run under real LuaJIT by `build.mjs`, using the bootstrap compiler's own
lexer to tell "real `const` keyword" from "the five characters c-o-n-s-t
inside a string that happens to hold generated-code *text*" (nupp.gen emits
literal `const` into the Lua it generates for a checked program, and doing
this with a regex over the raw file, as an earlier version of this script
did, means either missing that distinction — breaking on `const` used as an
ordinary field or variable name elsewhere in the compiler's own code — or
corrupting a string it shouldn't touch. `const` and `local` are the same
length, so the rewrite can't shift any later byte offset the ULL edits also
need). Needs this project's own `.rocks` on `LUA_PATH`, same as `bin/nupp`.

The `io.open` shim is why running with no manifest, no other files, and no
warm cache isn't a degraded mode here — it's the same "cache miss, recompute"
path a real first-ever build takes, per the project's own cache design (see
[`AGENTS.md`](../../AGENTS.md#speed)): corrupt or missing costs one slow
recompute and changes no answer, never a wrong one.

One more piece lives in `build.mjs` rather than `host-runtime.lua`: fengari's
own package assumes Node (`process.stdin`, `require("fs")`, …) in a few
places, including some that run the moment a module loads rather than when a
function is actually called. fengari already has a browser-safe branch for
most of these, gated on `typeof process === "undefined"` — the fix is
`define: { process: "undefined" }` in the esbuild config, the same technique
[fengari-web's own build](https://github.com/fengari-lua/fengari-web) uses,
so those branches fold to the browser-safe path at bundle time rather than
trying to resolve `fs`/`os`/`child_process` for real.

## What doesn't work: real C structs

`ffi` is the one stand-in that can't be a working implementation, because it
would need to be one: real struct/cdata layout (size, alignment, offsets)
depends on an actual C ABI, which requires a C compiler and a live process —
neither exists in a browser sandbox. Per the project's README, Nupp leans on
this directly: `record`/`struct` declarations are checked and lowered against
*real* `ffi.typeof`/`ffi.cast` results, not a reimplementation of C's layout
rules, so the checker gets exactly what LuaJIT would compile rather than a
guess at it.

So the playground's `ffi` stub fails loudly instead of guessing: any checked
program that reaches real C-type machinery — a `record` or `struct`
declaration, `ffi.cdef`, `import-c` — surfaces a clear message rather than a
wrong layout or a silent crash. Everything else — functions, generics, union
and gradual types, ownership over plain values, modules, control flow — type
checks with the same fidelity as `nupp check` on the command line, because
it *is* `nupp check`.

This mirrors the tradeoff [Luau's browser playground](https://luau.org) makes
running its C++ implementation compiled to WebAssembly: real execution stops
where the sandbox's abilities do.

## Two pages

**`index.html`** is the full playground: source editor, a diagnostics list
and generated-Lua panel behind tabs, a Compile button, header and footer.

**`embed.html`** is just the editor — no header, tabs, side panel, or
footer — meant for `<iframe src=".../embed.html">`. It still checks on every
edit with the same debounce and shows the same inline squiggles and hover
messages; the only UI is a small status pill in the corner. Both pages share
`app.js`, which looks up each optional panel element by id and skips
wiring it up when the page doesn't have one, rather than each page having
its own script.

## Layout

    src/
      host-runtime.lua   the shims above, loaded before bootstrap/nupp.lua
      worker.js           boots the Lua VM, drives check/compile, one JSON
                           message in, one back — see the top for the request
                           shape
      nupp-lang.js         CodeMirror syntax highlighting (Lua's stream mode
                           plus Nupp's extra keywords)
      app.js               the UI: editor, diagnostics panel, generated-code
                           panel, debounced check-on-edit — shared by both
                           pages, see "Two pages" above
      example.nupp          the starter snippet
      cm-theme.js            the editor's colors — see "Colors" below
      empty-shim.js         stands in for the Node built-ins (fs, path, os,
                           …) fengari's package statically requires but this
                           playground never reaches — see build.mjs
    static/                 index.html, embed.html, style.css, favicon
    tools/
      patch-bootstrap-for-browser.lua  the const/ULL fix above, run by build.mjs
    build.mjs                esbuild bundle: app.js and worker.js to dist/,
                             plus bootstrap/nupp.lua patched and copied in as
                             a fetched asset — dist/nupp-bootstrap.lua is
                             browser-safe, worker.js does no further patching
    serve.mjs                 a static file server for dist/, nothing more

## Colors

Every color in `static/style.css` comes from `docs/public/nupp.css` — the
real site's actual "woodblock" theme, layered as a `customCss` override on
top of `src/nupp/doc/assets.nupp`'s generic default (a plausible-looking but
wrong place to source colors from, since the whole point of that file is to
get overridden). `--pg-button` is that file's `--nupp-woodblock-vermilion`
exactly, one value in both light and dark, same as its own `.brand`
hero-action rule. `--pg-accent` departs from it on purpose: the real site's
own accent is a teal, kept there for links; here its string-syntax green
does UI-accent duty too.

`src/cm-theme.js` is a real CodeMirror `EditorView.theme` and
`HighlightStyle`, not loose CSS layered on top of `basicSetup`'s default one:
a plain `.cm-*` class override in `style.css` loses that specificity fight,
which is why the very first version of this file had it (a white gutter and
default reddish/orange token colors, regardless of the page's own dark
background).

## Development

    npm install
    npm run serve

Opens `dist/` on `http://localhost:8787`. `npm run watch` rebuilds on save
without serving; pair it with any static server pointed at `dist/`.

Both check and compile call directly into the same functions
`src/nupp/cli/check.nupp` and `src/nupp/cli/compile.nupp` call — this is not
a reimplementation of the CLI, just the CLI's own pipeline (`parser.parse` →
`check.check` → for compile, `nupp.optimize` → `nupp.gen`) driven from a
buffer instead of a file path, the same way `nupp lsp` drives it from an
open document.
