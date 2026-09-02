---
order: 1
redirects: learn/getting-started
---

# Getting started

The built-in application template creates a checked program, its test suite,
and the project tasks that run both. Start here when `nupp` is already on
`PATH`.

```bash
nupp init app hello
cd hello
nupp check
nupp test
nupp task start
```

The program is in `src/main.nupp`. Change the return type or pass an argument
of the wrong type, then run `nupp check` again to see the diagnostic and its
repair help.

## Daily loop

The generated project uses the same commands as a larger one:

```bash
nupp check       # check the configured source graph
nupp fmt --write # format project source
nupp test        # build and run configured tests
nupp build       # build the default deliverable
nupp task start  # run the project's start task
```

`nupp explain CODE` expands a diagnostic into its rule and a corrected
example. `nupp reference --for CODE` opens the relevant language section.

## Project templates

`nupp init --list` prints the maintained templates. Each template carries a
manifest, tests, and the tasks needed for its host.

- `app` creates a command-line application.
- `lib` creates a typed LuaRocks library.
- `browser` creates a portable Lua application hosted in a browser Worker.
- `browser-simd` adds scalar and SIMD128 Wasm AOT variants.
- `love` creates a checked LÖVE project with pinned API definitions.

## Continue learning

Read the [tour](tour.md) for the core language. Use the
[feature map](features.md) to find comptime, ownership, workers, AOT, GPU
compute, portable targets, embedding, and the standard library. The
[tooling guide](../learn/tooling/index.md) covers the daily commands in more depth.

Building Nupp itself from a source checkout is separate from creating a Nupp
project. See [installation.md](installation.md) when you need that workflow.
