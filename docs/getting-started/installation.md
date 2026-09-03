---
order: 5
redirects: learn/getting-started/installation
---

# Installation

Nupp releases are self-contained: the compiler, runtime, standard library, and
documentation tools travel in one platform archive. You do not need LuaJIT,
Rust, or a C compiler to start a Nupp project.

## Homebrew on macOS

The Homebrew tap supports Apple-silicon macOS:

```bash
brew install nupp-lang/tap/nupp
```

Upgrade later with:

```bash
brew update
brew upgrade nupp
```

The macOS release is currently unsigned. A browser download may make macOS ask
for explicit approval the first time it runs; use **Open Anyway** under
**System Settings > Privacy & Security** if that happens.

## Scoop on Windows

The Scoop bucket supports 64-bit Windows:

```powershell
scoop bucket add nupp https://github.com/nupp-lang/scoop-bucket
scoop install nupp
```

Upgrade later with:

```powershell
scoop update
scoop update nupp
```

## Direct downloads

The [latest GitHub release](https://github.com/nupp-lang/nupp/releases/latest)
provides these complete distributions:

| Platform | Archive |
| --- | --- |
| Linux x86-64 | `nupp-linux-x86_64.tar.gz` |
| Apple-silicon macOS | `nupp-macos-arm64.tar.gz` |
| Windows x86-64 | `nupp-windows-x86_64.zip` |

Extract the archive, put `nupp` or `nupp.exe` on `PATH`, and verify it:

```bash
nupp --help
```

Each archive includes its third-party notices, signing status, and a
`SHA256SUMS` file for the executable. The Linux and Windows distributions also
include the native compiler pack used for C FFI and ahead-of-time compilation.

## Build from source

Clone the repository only when you want to contribute to Nupp or work on the
compiler itself. The [contributing guide](../contributing.md) covers the pinned
Rust, C/C++, LuaJIT, LPeg, bootstrap, and worktree requirements without making
them prerequisites for ordinary users.

## Start a project

```bash
nupp init app hello
cd hello
nupp check
nupp test
nupp task start
```

Continue with [Getting started](index.md) for the project loop and templates.
