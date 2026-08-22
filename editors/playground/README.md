# Nupp Playground

The playground checks and compiles Nupp entirely in the browser. It runs the
real self-hosted compiler inside official Lua 5.1 compiled to WebAssembly, in a
module Worker and off the main thread. It does not reimplement the checker in
JavaScript and does not send source to a server.

## Compiler artifact

`nupp build --target playgroundCompiler` produces one Lua 5.1 source bundle.
The portable-compiler acceptance lane first runs those bytes unchanged in a
native official Lua 5.1 host that opens only base, package, table, string, math,
and coroutine. The build then gives the exact same bytes a content-addressed
filename and compiles their SHA-256 digest into the Wasm host.

The browser downloads four generated assets:

- `nupp-playground.mjs`, the Emscripten ES module loader;
- `nupp-playground.wasm`, official Lua 5.1 and the small C host;
- `nupp-compiler-<digest>.lua`, the separately cached compiler; and
- `nupp-playground-assets.json`, the artifact names, digest, and sizes.

The C host hashes the supplied compiler before Lua sees it and fails closed on
a mismatch. It uses `luaL_loadbuffer` directly and enables no Emscripten
virtual filesystem.

## Fast startup

Checking the standard prelude from source dominated the old compiler startup.
The portable target carries that already-checked type graph as inert data. A
small checked Nupp module hydrates a fresh graph for each output dialect; it
does not evaluate generated fallback code.

The source declarations remain authoritative. The acceptance test constructs
the graph from source and requires a byte-identical image, then hydrates the
image and requires the round trip to produce the same bytes. Table keys,
cycles, metatables, and shared identities are preserved. Ordinary native
compiler entries continue to check the prelude from source.

## Worker protocol

The UI keeps one stateful compiler session in `worker.js`. Requests retain the
same IDs and shapes for `check`, `compile`, and `hover`:

```js
worker.postMessage({
  id: 1,
  kind: "compile",
  source,
  filename: "playground.nupp",
  options: { strict: true, optimize: true, dialect: "lua51" },
});
```

The Worker passes that object through the compiler's JSON adapter. The C ABI
returns an owned response handle; JavaScript copies the bytes and frees the
handle on every path.

The full playground exposes Lua 5.1 and LuaJIT output, defaulting to Lua 5.1.
The VM hosting the compiler stays Lua 5.1 in both cases. Cross-dialect LuaJIT
output is validated by LuaJIT in the differential suite instead of being
misreported by the host parser.

## Host boundary

The browser compiler accepts one in-memory source file. It has no filesystem,
process, project resolver, persistent build cache, documentation renderer,
AOT host, or C-header parser. `cinterop` and `cstorage` are unavailable because
the browser supplies no native ABI or storage provider. Their diagnostics come
from the same dialect and capability machinery as command-line builds.

Declarations for standard modules remain available while checking source, but
the playground never executes the generated program. A library may therefore
compile against a dependency-backed runtime seam even though that dependency
is not installed inside the compiler Worker.

## Pages

`index.html` is the full playground. It has the example and output-dialect
selectors, check status, options, sharing, and generated output. The output
panel can be resized beside the editor and becomes a bottom drawer on narrow
screens.

`embed.html` is the standalone iframe form. Generated documentation normally
uses the `<nupp-playground>` element from `doc-app.js` instead, so editors share
one lazy Worker and CodeMirror popups remain in page space.

Strict checking and `-O1` optimization default on. Shared links store source,
dialect, and non-default options in the URL fragment, so none of them reach a
server.

## Development

Emscripten 6.0.8 is required. From this directory:

```bash
npm install
npm test
npm run serve
```

The build first proves the portable compiler under native Lua 5.1, builds the
Wasm host, hashes and copies the exact tested compiler bytes, and then bundles
the UI. `npm run test:wasm` runs the Node differential and digest-rejection
tests. The Chromium smoke page exercises the generated Worker through the same
static-server path used by Pages.

The relevant files are:

```text
src/app.js                 full and iframe UI
src/doc-app.js             inline documentation component
src/wasm-worker.js         live Worker and message protocol
src/wasm-runtime.js        Wasm allocation and handle ownership
src/examples/              checked standalone examples
static/                    pages, theme, and favicon
wasm/nupp_host.c           verified Lua 5.1 host ABI
tools/build-wasm-host.sh   pinned Emscripten build
build.mjs                  acceptance, hashing, host, and UI build
```

## Examples and theme

Every entry in `src/examples.js` names one file in `src/examples/`. Examples
must be standalone because the browser has no project filesystem. They must not
require native C layout, and each ends with a small edit that demonstrates a
diagnostic.

The colors in `static/style.css` follow the documentation site's woodblock
theme. `src/cm-theme.js` owns CodeMirror's editor and syntax styles so the full
playground, iframe, and inline documentation editors render the same language.
