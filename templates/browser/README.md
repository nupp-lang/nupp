# ${name}

A Nupp browser application. Ordinary code lowers to Lua 5.1 and runs in a
WebAssembly-hosted Lua VM. Checked providers use Web Crypto, browser timers,
randomness, and IndexedDB at suspension boundaries. The selected browser
backend also carries the standard HTTP provider for applications that need it.

```sh
nupp check
nupp build
nupp test
```

## Run it in a browser

Packaging currently uses the host builder from a Nupp source checkout. It needs
Node.js, Emscripten 6.0.8, and the official Lua 5.1.5 source directory:

```sh
export NUPP_SOURCE=/path/to/nupp
export NUPP_WASM_CC=/path/to/emsdk/upstream/emscripten/emcc
export NUPP_LUA51_SOURCE=/path/to/lua-5.1.5/src

nupp task package
nupp task serve
```

Open <http://127.0.0.1:8787>. The page executes the packaged Lua bundle in a
Worker, hashes random bytes with Web Crypto, waits on a browser timer, and
round-trips a value through IndexedDB. `dist/browser/nupp-browser-app.json`
records the verified, content-addressed assets and runtime limits.
