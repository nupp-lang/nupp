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
 `const NAME = value` nupp.compiler.build.hash's own top-level locals   rewritten to `local`, at build time
 `0x..ULL` literals    nupp.compiler.build.hash (content-hash cache)    stripped to plain Lua 5.3 ints, at build time
 `bit.*`               nupp.compiler.build.hash, nupp.compiler.cdecl         real bitwise ops, Lua 5.3 native
 `loadstring`          nupp.compiler.optimize's constant folder         Lua 5.3's `load`, same for a chunk
 both of the above     in code nupp.compiler.gen generates, re-loaded to check it   same two rewrites, at load time
 `unpack`              nupp.compiler.comptime's protected calls         Lua 5.3's `table.unpack`
 `string.buffer`       nupp.compiler.build.store (project-index cache)  a plain string-accumulator
 `cjson`               build cache, `--json`-shaped output     a small JSON codec
 `ffi`                 nupp.compiler.cdecl, nupp.compiler.check.ffi              stub, except `cast` — see below
 disk I/O              manifest/config lookup, project cache   `io.open`/`io.popen` return "not found"

The first two rows are fixed at *build* time, by
[`tools/patch-bootstrap-for-browser.lua`](tools/patch-bootstrap-for-browser.lua)
— run under real LuaJIT by `build.mjs`, using the bootstrap compiler's own
lexer to tell "real `const` keyword" from "the five characters c-o-n-s-t
inside a string that happens to hold generated-code *text*" (nupp.compiler.gen emits
literal `const` into the Lua it generates for a checked program, and doing
this with a regex over the raw file, as an earlier version of this script
did, means either missing that distinction — breaking on `const` used as an
ordinary field or variable name elsewhere in the compiler's own code — or
corrupting a string it shouldn't touch. `const` and `local` are the same
length, so the rewrite can't shift any later byte offset the ULL edits also
need). Needs this project's own `.rocks` on `LUA_PATH`, same as `bin/nupp`.

Those two constructs come back at *run* time, in the code the compiler
generates for the program in the editor: a program's own top-level `const`
declarations are emitted as LuaJIT `const`, and 64-bit constants as `ULL`
literals. `nupp.compiler.gen` loads what it just generated to prove it parses,
reporting NUPP3005 ("generated code does not load", a compiler bug) when it
does not — a check that reads the host VM's parser as the target's, which is
true under LuaJIT and false here. So `loadstring` in
[`src/host-runtime.lua`](src/host-runtime.lua) applies the same two rewrites,
with the same lexer, to a chunk this VM refused, and retries: the answer the
caller wants is the target's, and dropping the check instead would leave a
real malformed emission silent in the browser.

The `io.open` and `nupp.io.files` shims are why running with no manifest, no
other files, and no warm cache isn't a degraded mode here. The compiler's
directory walk moved from a shell command to the native files API; in the
browser that API reports an empty filesystem before its lazy native loader can
reach `ffi.cdef`. This is the same "cache miss, recompute" path a real
first-ever build takes, per the project's own cache design (see
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

`ffi.cast` is the exception, and only for what `nupp.compiler.build.hash` asks of
it: a read-only `const uint8_t *`, `uint32_t *` or `uint64_t *` view over a Lua
string, and the numeric `uint64_t` conversion beside them. Reading
little-endian words out of a string is not C-ABI work — there is no layout, no
alignment, and no offset the platform gets to decide — so it is one of the few
things this VM can answer exactly rather than guess at, and Lua 5.3's own
64-bit integers wrap where LuaJIT's `uint64` does. Everything else on `ffi`
still fails loudly.

That aside, `ffi` is the one stand-in that can't be a working implementation, because it
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

Both are the same three parts: a bar naming the buffer with the actions on its
trailing edge, the editor, and the compiler's answer in a panel of its own.
What differs is how much room each has, and so where that panel goes.

**`index.html`** is the full playground: a header with the example menu, the
check status, Options, Share and Run. The answer stays out of the way until Run
is clicked, then opens down the right-hand side. The output is the top of that
panel and the diagnostics list is under it. Both edges move: drag between the
editor and the panel to give the answer more or less of the window, and between
the two halves of the panel to split it differently. Double-click either to put
it back. Under about 720px there is no room for two columns, so the panel
becomes the embed's drawer along the bottom and the same edge drags up and down
instead.

**`embed.html`** remains the self-contained version for a site that explicitly
wants an iframe. Run and Open sit above the editor's border at the right, while
Options stays in the full playground.

Nupp's own documentation does not use that iframe. Its `nupp` and
`playground` fences render as `<nupp-playground>` elements in the page itself;
`src/doc-app.js` defines that component. The editors size from their actual
content, their CodeMirror popups can paint in page space, and the page shares
one lazy compiler worker between all of them. Run reveals an output panel with
a close control, while Open hands the current buffer to the full playground.

The panel answers one question — what did the compiler say. Its main pane
holds the diagnostics as the CLI prints them when something is wrong, and the
generated Lua when nothing is; the list stays either way, because a clean
compile can still carry warnings. index.html highlights that pane as Lua,
which is why a diagnostic run is written as Lua comments: one report format
reads correctly in both.

The two arrangements are one set of parts, not two: `static/style.css`
describes the drawer once and then says which way each piece runs on the page
that has a `.shell`, and `src/app.js` has one resizable-pane implementation
that reads its axis off the layout rather than being told — which is also what
lets a separator keep working when that media query turns a row into a column
under it.

**Options** sets what the compiler is asked for: strict or gradual checking,
and whether the `-O1` passes run before Lua is generated. Strict is on by
default here where the command line leaves it off — every bundled example
checks clean under it, and a playground is where the stricter answer is the
more interesting one to meet first.

An embedding page may supply its own program, as `#source=` in the fragment,
percent-encoded, and non-default options ride along beside it (`&strict=0`).
Share, on the full playground, builds exactly that link and copies it; where
the clipboard is refused — an insecure origin, some embeddings — it puts the
link in the address bar and says so. The fragment, rather than a query, keeps
a reader's program and edits from reaching any server.

A page that inlined its own program has one buffer and has already chosen it,
so the embed's head bar shows neither a synthetic filename nor the example
menu. The full playground keeps the menu regardless: a reader who arrived on a
shared link is still free to go browse.

Both pages share `app.js`, which looks up each optional element by id and skips
wiring it up when the page doesn't have one, rather than each page having its
own script.

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
      doc-app.js           the inline custom element used by generated docs;
                           all instances on a page share one compiler worker
      examples.js          the example picker's menu, in order — the first
                           entry is what the editor opens on
      examples/            one .nupp file per menu entry — see "Examples"
                           below for what belongs in one
      cm-theme.js            the editor's colors — see "Colors" below
      empty-shim.js         stands in for the Node built-ins (fs, path, os,
                           …) fengari's package statically requires but this
                           playground never reaches — see build.mjs
    static/                 index.html, embed.html, style.css, favicon
    tools/
      patch-bootstrap-for-browser.lua  the const/ULL fix above, run by build.mjs
    build.mjs                esbuild bundle: app.js, doc-app.js and worker.js to dist/,
                             plus bootstrap/nupp.lua patched and copied in as
                             a fetched asset — dist/nupp-bootstrap.lua is
                             browser-safe, worker.js does no further patching
    serve.mjs                 a static file server for dist/, nothing more

## Examples

`src/examples.js` is the whole menu: the dropdown's options are built from
it at load, so a snippet can't be offered without existing or exist without
being offered. Adding one is a file in `src/examples/` and a line there.

Three constraints come from where these run rather than from taste. Each is
a standalone program: the playground checks one buffer with no filesystem
behind it, so nothing can `require` anything else. None may declare a
`struct`, `cdef`, or `cheader` — that is exactly the C-ABI machinery the
`ffi` stub above can't stand in for, so such an example would open on an
error about the playground rather than on the language.

And none may use syntax newer than `bootstrap/nupp.lua`, because that bundle
is the compiler this page runs. `./bin/nupp check` runs `build/` instead — a
compiler that has kept up with the sources — so it is the wrong thing to
check a snippet with and will pass one the page cannot parse. Check with the
compiler the page actually has, from the repository root:

    luajit bootstrap/nupp.lua check editors/playground/src/examples/NAME.nupp

Variadic generics (`A...`) are on the wrong side of that line as of this
writing, which is why there is no type-pack example here yet; a
`nupp fixpoint --update-bootstrap` is what moves the line.

Each ends with a "try breaking it" line naming an edit and the diagnostic it
draws, because the thing worth showing here is the one a static code sample
on a docs page can't: what the checker says when the program is wrong.

## Colors

Every color in `static/style.css` comes from `docs/public/nupp.css` — the
real site's actual "woodblock" theme, layered as a `customCss` override on
top of `src/nupp/compiler/doc/assets.nupp`'s generic default (a plausible-looking but
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
`src/nupp/compiler/cli/check.nupp` and `src/nupp/compiler/cli/compile.nupp` call — this is not
a reimplementation of the CLI, just the CLI's own pipeline (`parser.parse` →
`check.check` → for compile, `nupp.compiler.optimize` → `nupp.compiler.gen`) driven from a
buffer instead of a file path, the same way `nupp lsp` drives it from an
open document.
