# Resume the Nupp native core migration

Updated November 21, 2026. Every lane this page used to list has landed
on `core-dev`. The work left is tracked in issues, not here.

- [#138](https://github.com/nupp-lang/nupp/issues/138): the shared lane
  on the native core, case by case. This is what stands between any host
  and `STAGE0_CORE_HOSTS`.
- [#134](https://github.com/nupp-lang/nupp/issues/134): the Windows CI
  legs on ARM64.

## Seeds

| Host | Release | Pinned |
| --- | --- | --- |
| `aarch64-apple-darwin` | `v0.0.15-core-seed.2` | `88b088762` |
| `aarch64-unknown-linux-gnu` | `v0.0.15-core-seed.3` | `2191d4aec` |
| `aarch64-pc-windows-gnullvm` | `v0.0.15-core-seed.4` | `4a1ddae7d` |

Each seed passed a native fixpoint and an offline cold reinstall that
reproduced its compiler byte for byte, with the Rust VM refused.
`STAGE0_CORE_HOSTS` is still empty. Only the owner adds a host to it or
publishes a seed.

## Building a native compiler from a checkout

Install a `core-dev` compiler with a bridge built from the same checkout,
not the seed's `runtime`. The seed's bridge lacks symbols newer sources
call, and it stops at a `BRK` on launch.

```sh
seed=$(sh scripts/toolchain core-seed)
sh scripts/core-bridge
sh scripts/core-self-build core "$seed/runtime" "$seed/compiler.bundle" \
  "$PWD/build/handoff-core"
sh scripts/core-cli install "$PWD/build/c-core-bridge/nupp-core" \
  "$PWD/build/handoff-core/compiler.bundle"
NUPP_RUNTIME=core NUPP_CORE_AUTO_REBUILD=0 ./bin/nupp --version
```

The compiler bundle embeds the runtime, the standard library and the
compiler modules the tests load. A source edit needs a native rebuild
before a core test run sees it. A compiler bundle also records the
checkout's absolute path, so compare two builds byte for byte only when
both came from the same path.

On Windows ARM64, build under MSYS2's `clangarm64` environment. Its
`scripts/core-bridge` produces `nupp-core.exe` with libuv, curl, OpenSSL
and zlib linked in statically. `.github/workflows/windows-arm64.yml` runs
the same steps on the `windows-11-arm` runner.
