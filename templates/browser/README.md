# ${name}

A Nupp browser application. Ordinary code runs in LuaJIT inside a
WebAssembly-hosted i386 guest. Checked providers use Web Crypto, browser timers,
and randomness at suspension boundaries. The selected browser
catalog also carries the standard HTTP provider for applications that need it.

```sh
nupp check
nupp build
nupp test
```

## Run it in a browser

Packaging currently uses the host builder from a Nupp source checkout. It needs
Node.js and the pinned browser guest package:

```sh
export NUPP_SOURCE=/path/to/nupp
export NUPP_BROWSER_GUEST_DIR=/path/to/browser-guest

nupp task package
nupp task serve
```

Open <http://127.0.0.1:8787>. The page executes the packaged Lua bundle in a
Worker, hashes random bytes with Web Crypto, and waits on a browser timer.
`dist/browser/nupp-browser-app.json` records the verified, content-addressed
assets and runtime limits.

The guest includes its matching sources and notices; redistribute these with the
application. FFI uses guest i386 libraries. Browser APIs are supplied by host
adapters.
