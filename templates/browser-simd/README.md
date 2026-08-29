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

Packaging needs a Nupp source checkout, Node.js, Emscripten 6.0.8, and the
official Lua 5.1.5 source directory:

```sh
export NUPP_SOURCE=/path/to/nupp
export NUPP_WASM_CC=/path/to/emsdk/upstream/emscripten/emcc
export NUPP_LUA51_SOURCE=/path/to/lua-5.1.5/src

nupp task package
nupp task serve
```

Open <http://127.0.0.1:8787>. `src/scalar.nupp` forces scalar AOT and
`src/simd.nupp` forces lane lowering into Wasm SIMD128. Both operate over Nupp
struct arrays in the Lua host's linear memory. The page reports which package
it selected and the kernel's result. Measure representative application
buffers before deciding that an AOT boundary pays for itself.

Append `?scalar` to the example URL to exercise the fallback on a browser that
supports SIMD128.
