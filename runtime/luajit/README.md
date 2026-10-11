# LuaJIT browser runtime

LuaJIT is the browser runtime. The legacy Lua 5.1 browser backend has been
removed; see [migration and remaining limits](MIGRATION.md).
`guest-manifest.json` identifies every input and output by SHA-256. Guest
artifacts come from source, rather than the spike's downloaded root filesystem.

Build on Linux x86_64 with Python 3.12+, GCC/G++ multilib, make, binutils,
flex, bison, libelf-dev and libssl-dev:

```sh
./scripts/toolchain browser-guest
```

On other platforms, `browser-sources` verifies/provisions the same sources;
`NUPP_PYTHON` selects a Python interpreter. These commands use the existing
`NUPP_HOST_SOURCE_DIR`, `NUPP_HOST_SOURCE_BASE_URL`, `NUPP_HOST_OFFLINE` and
`NUPP_TOOLCHAIN_DIR` controls. The opt-in inputs are pinned in
`scripts/toolchain.pins`. Native `--all` does not download the browser kernel.

Each build carries `matching-source.tar.gz`, upstream notices and the resolved
Linux/SeaBIOS configurations. The source bundle includes the exact archives,
recipes and local changes. Distributors must carry those artifacts with the
runtime. Kernel and firmware licenses differ from the v86 emulator license;
see the actual notices rather than treating the entire package as BSD.

The 64 MiB application and 128 MiB compiler profiles reserve eight MiB for a
bounded mailbox. Initialization stops before LuaJIT is launched. Every restore
writes fresh configuration, application code, 256 bits of browser entropy and
wall time before starting a new LuaJIT process. The snapshot includes no
application VM, credentials, service handles or live JIT traces.

The compiler lane sends source outside its JSON envelope and retains one
compiler session. A busy request is cancelled by terminating its worker/VM;
the next request starts a fresh session. Guest FFI sees only i386 Linux guest
libraries. Browser timers, entropy, crypto, storage, HTTP, worker tasks and WebGPU use
bounded copied transfers. Independent Wasm kernels use a separate memory and
scalar/span ABI. Lua-C-API builders use guest-native AOT shared libraries with
`aot = "require"`, the i686 target and a musl cross compiler. They execute inside
the real guest LuaJIT and share its objects; they are not independent Wasm kernels.

A same-origin deployment can allow `script-src 'self' 'wasm-unsafe-eval'`,
`worker-src 'self' blob:` and the application's required `connect-src`
destinations. The emulator uses a blob Worker for compilation. Browser tests
exercise this policy without COOP/COEP; the UI also needs its usual stylesheet
policy. Test the exact deployment headers before publishing.
