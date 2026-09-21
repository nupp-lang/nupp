# Nupp Playground

The playground checks, compiles and runs Nupp entirely in the browser. The
self-hosted compiler runs in LuaJIT inside a v86 Worker; each application runs
in a separate guest. Source stays on the user's device.

## Build and serve

Install the pinned native toolchain and playground dependencies, then build:

```sh
./scripts/toolchain --all
npm ci --prefix editors/playground
npm run build --prefix editors/playground
npm run serve --prefix editors/playground
```

The LuaJIT guest is built from pinned sources on Linux x86_64. Other development
hosts set `NUPP_BROWSER_GUEST_DIR` to a verified source-built guest package.
See [guest requirements](../../runtime/luajit/README.md). Emscripten 6.0.8 is
needed when packaging independent Wasm kernels.
The build creates missing pre-LuaJIT snapshots in a derived build cache using
headless Chromium; it does not modify the toolchain's source package.

`scripts/prelude-image luajit` builds the compiler and checks its prelude image
round trip. The compiler bytecode, application initializer, emulator and clean
snapshots are compressed, content identified and verified before use. Matching
guest sources and notices accompany the static distribution. HTTP caching and
compression for JavaScript/CSS remain the static host's responsibility.

## Compiler Worker

The UI retains one stateful compiler session for checks, compilation and hover:

```js
worker.postMessage({
  id: 1, kind: "compile", source, filename: "playground.nupp",
  options: {strict: true, optimize: true, dialect: "luajit"},
});
```

Requests use the existing JSON response shape, with source bytes outside the
JSON envelope at the guest boundary. Pending checks are coalesced; the queue
holds at most 32 requests. Source is capped at 1 MiB. Closing or stopping the
compiler terminates its guest; the next check creates a new session. Old worker
responses cannot update a replacement editor session.

The compiler uses 128 MiB guest RAM. Snapshots precede LuaJIT startup, so no
user code, compiler session, live resources or JIT traces are shared between
users. Each restore injects fresh entropy, time and configuration. A rejected
snapshot falls back to normal boot of the same verified guest.

## Application Worker

Run compiles the source and starts a fresh 64 MiB guest. It captures output and
uses browser providers for timers, Web Crypto, HTTP and WebGPU.
Native guest FFI, `bit`, `string.buffer` and LPeg remain available. FFI addresses
belong to the i386 guest; they are not browser addresses. Browser services use
bounded copied leases, never shared guest pointers.

Each playground run has a five-second execution deadline, 128 effects, a
2 MiB effect-byte budget and a 4 MiB response budget.
Startup has its own deadline. Stop terminates the application Worker even if
code never yields. The compiler remains available for later edits.

The guest RAM settings are not total browser memory: Wasm memory, JavaScript,
snapshot decoding and generated emulator code also contribute. No
SharedArrayBuffer or cross-origin isolation headers are required.

## Compatibility

LuaJIT is the default runtime. The options menu's stock Lua 5.1 compatibility
checkbox enables `compat = "lua51"`: unsupported source and dependencies are
rejected without selecting a different generator or VM. It is narrower than
the removed portable lowering contract. Settings survive reload and shared URL
fragments carry source and non-default options. Strict checking and O1
optimization default on.

## Host boundary

The compiler handles one in-memory source file, including inline C declarations
and i386 layout inspection. It has no project filesystem, process launcher,
local-header preprocessor or browser AOT compiler. Build applications with
independent Wasm kernels using the CLI's browser target and package command;
see [runtime migration](../../runtime/luajit/MIGRATION.md).

The runtime carries the standard modules used by the examples and browser
providers. An external module must be packaged explicitly. A dependency that
checks successfully is not a promise that its host facilities exist in a browser.

## Pages and tests

`index.html` is the full playground; `embed.html` is the iframe form. Generated
documentation uses `<nupp-playground>` from `doc-app.js`, sharing one lazy
compiler Worker. Component removal and page teardown cancel application work.

`npm test` covers the UI helpers. `test/luajit-ui.mjs` exercises the built UI in Chromium, Firefox
and WebKit. `test/compiler-performance.mjs` measures the actual retained workers
with changing source, and `test/delivery.mjs` measures cold/cached navigation
under a shared modeled 10 Mbps transfer budget. Engine tests are not physical
mobile-device or shipping Safari acceptance.

## Examples and theme

Every entry in `src/examples.js` names one file in `src/examples/`. Examples
must be standalone because the browser has no project filesystem. Inline C
declarations and guest-native layouts are supported; local header files and host
preprocessing are not available. Examples should end with a small edit that
demonstrates a diagnostic.

The colors in `static/style.css` follow the documentation site's woodblock
theme. `src/cm-theme.js` owns CodeMirror's editor and syntax styles so the full
playground, iframe, and inline documentation editors render the same language.
