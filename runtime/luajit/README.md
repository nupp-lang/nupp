# LuaJIT browser runtime candidate

This branch is building an explicit LuaJIT browser candidate. It is not the
browser default, and it does not yet replace the packaged Lua 5.1 runtime.
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
libraries. Browser services and Wasm side-module migration require their own
adapters and conformance checks before this can replace the existing host.
