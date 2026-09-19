# ${name}

A Nupp browser application with two AOT builds of the same struct kernel. The
loader validates the SIMD128 side module before starting an application and
uses the scalar AOT package when SIMD is unavailable.

The default target keeps the scalar kernel as ordinary Lua so the project can
be checked, built, and tested without a C toolchain:

```sh
nupp check
nupp build
nupp test
```

## Build both Wasm variants

Packaging needs a Nupp source checkout, Node.js, Emscripten 6.0.8, and the pinned browser guest package:

```sh
export NUPP_SOURCE=/path/to/nupp
export NUPP_WASM_CC=/path/to/emsdk/upstream/emscripten/emcc
export NUPP_BROWSER_GUEST_DIR=/path/to/browser-guest

nupp task package
nupp task serve
```

Open <http://127.0.0.1:8787>. `src/scalar.nupp` forces scalar AOT and
`src/simd.nupp` forces lane lowering into Wasm SIMD128. Both operate on bounded copies of guest struct arrays. The bridge converts field offsets between the guest and Wasm layouts. The page reports which package
it selected and the kernel's result. Measure representative application
buffers before deciding that an AOT boundary pays for itself.

Append `?scalar` to the example URL to exercise the fallback on a browser that
supports SIMD128.

The guest includes its matching sources and notices; redistribute these with the application. FFI uses guest i386 libraries. Browser APIs are supplied by host adapters.
