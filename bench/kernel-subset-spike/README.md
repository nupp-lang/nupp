# Checked native-C Tecs subset spike

This spike compiles a Tecs-shaped function written as ordinary Nupp into a
verified AOT IR and private scalar C. Clang chooses unrolling, vector width,
instruction selection, register allocation, and tail handling. `@kernel` is a
test-only annotation; the production design calls the contract `@aot`.

The source remains the semantic implementation. Turning AOT compilation off
builds that same function through the ordinary Nupp backend. Enabling AOT
compilation makes every unsupported annotated construct a build error.

## Build modes

```sh
# Required native host library plus the ordinary oracle.
bench/kernel-subset-spike/build.sh

# No C generation or C compiler. The annotation erases normally.
NUPP_NATIVE_MODE=off bench/kernel-subset-spike/build.sh

# Produce verified private C without compiling it.
NUPP_NATIVE_MODE=emit-c bench/kernel-subset-spike/build.sh

# Produce an object with a selected target compiler and sysroot.
NUPP_NATIVE_MODE=object \
NUPP_NATIVE_CC=aarch64-none-elf-clang \
NUPP_NATIVE_CFLAGS="--sysroot=/path/to/sdk" \
bench/kernel-subset-spike/build.sh
```

`object` never executes target-built code. A console build can feed the C to
its vendor compiler, while a console configuration with AOT compilation
disabled retains the ordinary Nupp implementation. This spike does not pretend
to know any console SDK's linker or packaging rules.

After the required host build:

```sh
luajit bench/kernel-subset-spike/test.lua
luajit bench/kernel-subset-spike/main.lua
```

## Implemented Tecs-shaped subset

The one annotated function may currently use:

- readable `exclusive WriteSpan<T>` values and a checked `getMut(i)` element
  reference whose lifetime is tied to the writer;
- one or more shared `Span<T>` inputs and multiple disjoint writable columns;
- flat Nupp `struct` elements containing `float`, `int32`, and `uint32` fields;
- generated size and per-field offset checks before the native body is exposed;
- full-span loops or an inclusive `[first,last]` range with an ordinary Nupp
  range guard, including the empty `1..0` range;
- `float`, `number`, `integer`, `int32`, and `uint32` uniforms;
- mutable locals, simultaneous multiple assignment, struct field assignment,
  branches, scoped blocks, `break`, and `continue`;
- `+`, `-`, `*`, `/`, `%`, `^`, comparisons, booleans, unary operations, and
  LuaJIT-compatible 32-bit bit/shift operations;
- pure statically resolved helpers with one or several scalar results; and
- closed `math` lowering for `sqrt`, `abs`, `floor`, `ceil`, `min`, `max`,
  trigonometric and hyperbolic functions, `atan2`, `exp`, `log`, `pow`, `fmod`,
  `deg`, and `rad`.

The example is normal Nupp. It declares `Transform2D` and `Motion`, projects a
writable and readable component column, updates only a requested archetype row
range, calls a two-result helper, mutates locals, writes several fields, and
uses integer flags. There is no C-shaped expression API in the source.

## Safety and semantics

Every span has an explicit IR region. Every pair containing a writable span is
proved disjoint; shared inputs may alias. Generated C uses `restrict` only for
the proved writable regions.

Float storage loads widen to binary64, ordinary arithmetic stays binary64, and
stores narrow once. Fixed-width integer storage and bit operations have
explicit conversions; shifts mask their count to five bits as LuaJIT does.
The C build disables contraction and fast math.

Correctness compares all `Transform2D` bytes across ordinary Nupp, an
equivalent raw LuaJIT loop, forced-scalar C, and optimized C for zero through
33 rows, partial ranges, and a larger nontrivial range. It also exercises
length and range failures. The forced-scalar and optimized functions come from
the same verified IR.

The generated wrapper validates the range and all span lengths, projects typed
span pointers once, and calls C once per archetype range. Nupp structs currently
have no name usable in a `cdef` signature, so compiler-owned glue uses private
`void*` ABI slots after verifying the Nupp and C layouts. User source never sees
that erasure. Giving reified Nupp structs a private generated C spelling remains
a compiler feature needed before production.

## Remaining boundary

This is still a spike, not the production pass. It verifies structured mutable
slots rather than a full SSA graph, handles flat structs rather than nested
structs/fixed arrays, accepts one annotated function, and has no status-return
model for failures inside the loop. It does not yet implement native module
call graphs, reductions, stencils, target artifact validation, hot reload,
code-size budgets, inspection commands, or a target SDK registry.

Allocation, Lua tables, strings, dynamic calls, closures, metamethods,
coroutines, arbitrary FFI, and owned resources remain outside the subset.
Closed transcendental calls are semantically supported but commonly inhibit
auto-vectorization; their availability is not a SIMD promise.
