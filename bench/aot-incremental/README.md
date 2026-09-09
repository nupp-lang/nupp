# Ahead-of-time rebuild benchmark

What a second build of an `@aot` project costs, and what it did to cost that.

```sh
./run.sh            # every shape, three repetitions, the fastest of each
./run.sh 5          # five
SHAPES="wide" ./run.sh
NUPP=/elsewhere/bin/nupp ./run.sh   # the other half of a before/after pair
```

Each shape is generated rather than committed, because what distinguishes them
is how many files there are:

| Shape | What it is |
| --- | --- |
| `small` | one module with one `@aot` body |
| `multisource` | eight modules, one body each |
| `multiversion` | four modules built for x86-64, so each body is several objects |
| `wide` | sixteen modules built for x86-64: thirty-three objects |
| `wasm` | four modules under `require-wasm`, one Emscripten side module each |

Three states are timed for each: **cold** with no build directory, **unchanged**
immediately after, and **one edit** after a literal inside one module's `@aot`
body is changed. Beneath each row the run prints the `timing.aot` object the
build reported for the last unchanged and edited build, which is where the
claims worth making live:

- an unchanged build reports `externalCommands: 0`. No C compiler, no linker,
  no Emscripten, not even a version probe.
- a one-unit edit reports `compiledObjects` equal to the number of feature tiers
  the target carries -- one on aarch64, two here, three for an unrestricted
  x86-64 build -- and one link.

Wall-clock timings from here are worth what the machine was doing at the time,
which is why `run.sh` prints nothing about them and reports the minimum of the
repetitions rather than the mean. Record the load average beside any number
taken from it, and compare two compilers by alternating between them rather than
by running one and then the other.

`multiversion` and `wide` need a C compiler that can produce x86-64 objects. An
x86-64 machine is one; an Apple ARM64 machine is one, through its own SDK.
Elsewhere they need a sysroot the machine may not have.

`wasm` needs the pinned Emscripten on `PATH`, and reports it rather than
skipping when there is none.
