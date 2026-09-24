# LLVM as a lazy component: cached shared libraries (2026-09-24)

Throwaway evidence for the gate in `backend-direction-review.md`: does LLVM
work as a component that runs only on an AOT cache miss, with lld linking
what it compiles into a shared library the OS loads, so that no consuming
process carries LLVM? Not for merging.

## Verdict

<!-- VERDICT -->

## What was built

`spike/llvm-artifact/`, beside the two earlier spikes, sharing their front
half (`sem.rs`, `lir.rs`) and the LLVM lowering (`llvm.rs`) unchanged except
for a target-triple override and the JIT compiled out.

- **`component/`: `nupp-llvm`, a separate executable.** It holds the
  size-built LLVM 23.1.1, the lowering, and lld's Mach-O, ELF, COFF/MinGW
  (and optionally Wasm) drivers, called in process through `lld::lldMain`.
  - `compile`: one module holds the five kernels, `waves` and the three Lua
    builders. It is optimized at `default<O3>` with loop and SLP
    vectorization, interleaving and unrolling on. It is compiled to one
    object and linked by lld into `module.dylib`, `.so` or `.dll`. The entry
    directory is written beside its key and appears by one `rename`.
  - `exe`: links a cached object with the runtime's prebuilt objects and
    LuaJIT's static archive into a standalone macOS executable. The only
    other input is a libSystem text stub the component writes itself.
  - For a DLL, the component writes an import library per providing DLL
    (`writeImportLibrary`, what `llvm-dlltool` does), from rules the host
    passes: `lua_`/`luaL_` from `lua51.dll`, `ks_rt_` from `runtime.dll`, the
    rest from `msvcrt.dll`.
- **`host/`: `nupp-artifact-host`, which links no LLVM.** It stands in for the
  Nupp host on the consuming side.
  - It keys the cache by SHA-256 over the component's identity, the target,
    the instruction selector, the unwind setting, the builder size, the
    import rules and every input byte.
  - On a miss it starts the component and waits. On a hit it never touches
    the component; with the component deleted, a warm run still passes.
  - It loads the entry with `dlopen`/`LoadLibrary` and nothing else: no
    relocation, binding or unwind registration of its own.
  - It runs the LLVM spike's checks unchanged in substance (`harness.rs`).
- **`prepare.sh`**: the C oracle and the runtime (the C backend's builder C
  plus the `ks_rt_*` shims), built by the system C compiler. They are test
  fixtures and the product's own build, not the user's; nothing on the
  component's or the host's path calls a system tool.
- **`build-llvm.sh`**: the pinned LLVM. It fetches the 23.1.1 source tarball,
  verifies the digest Homebrew pins, and builds the MinSizeRel configuration
  of `LLVM.md` (AArch64, X86, WebAssembly; lld; nothing optional).
- **`run.sh`**: every check and measurement on the platform it runs on.
  `.github/workflows/spike-llvm-artifact.yml` runs it on Linux x86-64 and
  Windows x86-64 MinGW, on this branch only.

**Why an executable rather than a dylib.**

- An LLVM fatal error (`report_fatal_error`, an assertion in a release
  build, an out-of-memory abort) ends the component, not the user's program.
- LLVM's global state (`cl::opt`, the pass registry, signal handlers) never
  enters the host.
- A compile can be killed on a deadline, or run in parallel with others.
- It ships and signs as one more executable on every OS, with no C++ runtime
  or ABI to match against the host.
- The cost is process creation: 5.96 ms to exec and exit `nupp-llvm
  version`, against 0.88 ms for `/usr/bin/true`. About 5 ms of that is dyld
  and LLVM's static initializers, which a `dlopen`ed component pays as well.
  So a dylib would save about 1 ms, plus the pipe, of a cold miss.

## Commands

```sh
cd spike/llvm-artifact
(cd component && CARGO_TARGET_DIR=../../../build/component cargo build --release)  # LLVM tree: .cargo/config.toml
(cd host && CARGO_TARGET_DIR=../../../build/host cargo build --release)
./run.sh ../../build/component/release/nupp-llvm ../../build/host/release/nupp-artifact-host ../../build/results
# one step at a time (A = --kernels --builders --cache --component --luajit --runtime, as run.sh builds them)
$HOST check $A --oracle fixtures/oracle.dylib --verify [--isel fast|global]
$HOST bench $A --cold --runs 21 [--isel ...];  $HOST bench $A --warm --runs 21
$HOST time  $A --oracle fixtures/oracle.dylib --variants dag,fast,global
nupp-llvm exe --input main.o --input runtime.o --input oracle.o --input <entry>/module.o --input libluajit-5.1.a --out prog
./build-llvm.sh ../../build/llvm-mingw -DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ -DLLVM_HOST_TRIPLE=x86_64-w64-windows-gnu -DLLVM_NATIVE_TOOL_DIR=<native tree>/bin ...
```

<!-- BODY -->
