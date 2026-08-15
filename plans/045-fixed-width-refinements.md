# Fixed-width names as checked refinements

> **Status: implemented.** The checked refinements, storage projection,
> establishment facts, explicit conversions, diagnostics, and physical-store
> boundary described here are part of the compiler and standard library.
>
> This is a consistency fix, not a new arithmetic model. `integer` is already a
> checked refinement of `number` with no representation or operator promotion
> of its own. This plan applies that rule to the fixed-width names that can be
> represented exactly as Lua numbers, while keeping narrower layout-only names
> out of value positions.

## Decision

`float`, `int32`, and `uint32` become checked refinements of `number`:

- they denote unboxed Lua numbers in the corresponding fixed-width value set;
- widening to `number` is implicit and emits nothing;
- entering a refinement requires an establishing operation;
- ordinary arithmetic over them still yields `number`;
- an erased assertion may claim the type but does not establish the value.

`int8`, `int16`, `uint8`, and `uint16` become storage-position-only names. They
remain valid in reified struct fields, C arrays, span element positions, and
`cdef` declarations, but are diagnosed on ordinary locals, parameters, returns,
record fields, and general-purpose generic arguments. A load widens them into a
value refinement: signed storage loads produce `int32`, and unsigned storage
loads produce `uint32`.

`int64` and `uint64` remain outside this model. Their complete value sets are
not representable in binary64 and LuaJIT represents them as boxed cdata.

No operator acquires binary32 or wrapping semantics. No scalar becomes cdata,
no metatable appears, and no accepted program silently changes bits. Existing
source that made an unproved fixed-width claim receives a diagnostic and must
either widen the annotation or establish the value.

## What is broken today

A fixed-width annotation in a value position currently asserts something that
nothing establishes:

```nupp
function m.f(a: number): number
    local s: float = a
    local c = a as float
    p.x = p.x + p.y * a
    return s + c + p.x
end
```

The generated Lua is effectively:

```lua
function m.f(a)
    local s = a
    local c = a
    p.x = p.x + p.y * a
    return s + c + p.x
end
```

Only the reified `p.x` store narrows. A table-backed record field does not:

```nupp
local record R
    x: float
    n: uint32
end
```

Today `r.x = a` stores `a` unchanged, and a `uint32` record field may hold
`-0.5`. Meanwhile `local i: integer = a` is already rejected because `number`
does not establish `integer`. The fixed-width names are inconsistent with the
refinement rule the language already uses.

This becomes load-bearing under AOT. An AOT parameter written `scale: float`
cannot lower to C `float` merely because its static type has that spelling: an
erased `as float` may have manufactured the type without establishing the
value. AOT must consume establishment evidence, not the annotation alone.

## Value and storage model

### Value refinements

The value refinements are:

- `float`: every finite, infinite, signed-zero, or NaN value obtainable by
  storing a Lua number as binary32 and loading it back;
- `int32`: integral Lua numbers in `[-2^31, 2^31)`;
- `uint32`: integral Lua numbers in `[0, 2^32)`.

Their declared widening relationships are:

```text
float  <: number
int32  <: integer <: number
uint32 <: integer <: number
```

These are the language relationships, not a request to infer every accidental
set inclusion between integer ranges and exactly representable floats.

A refinement changes checking, not representation. At runtime all three remain
ordinary Lua numbers. Widening is the identity operation.

### Storage-only widths

`int8`, `int16`, `uint8`, and `uint16` describe layouts rather than values. The
compiler needs one storage-to-value projection:

| Storage element | Loaded value type |
| --- | --- |
| `int8`, `int16` | `int32` |
| `uint8`, `uint16` | `uint32` |
| `int32` | `int32` |
| `uint32` | `uint32` |
| `float` | `float` |

This projection applies to struct fields, fixed and variable C arrays, spans,
and `cdef` results. It is new type-system support. In particular,
`Span<int8>.get` cannot continue to mean that an `int8` value escapes into a
local; its instantiated read type is `int32`. The corresponding store still
targets the declared `int8` layout.

General generic code may not instantiate an unconstrained value parameter with
a storage-only width. Compiler-known reified element positions, including the
span element parameter, admit them and apply the projection above. Do not ship
the storage-only restriction until this works uniformly in checking, hover,
module summaries, and instantiated method signatures.

## Establishment is a dataflow fact

The static type and the fact that a runtime value has been established are
related but distinct. The checker records an internal establishment fact on an
expression or binding. It is not another user-facing type.

These operations establish a refinement:

- a reified load with that projected value type;
- the result of its explicit conversion;
- the result of a fixed-width intrinsic;
- an exactly fitting literal;
- a read from a checked record field whose writes require establishment;
- a refined parameter after a checked call supplied an established argument.

Assignment, argument passing, return, record construction, and record-field
writes preserve the fact only when their source has it. Widening to `number`
does not need the fact.

### Erased `as` does not establish

`e as T` remains an erased assertion. It may claim a refinement type, but it
does not manufacture establishment evidence:

```nupp
local claimed = input as float
local wide: number = claimed                  -- valid identity widening
local exact: float = claimed                  -- rejected: not established
nupp.math.f32.mul(claimed, establishedFloat)  -- rejected for the same reason
```

This keeps `as` uniform and prevents it from unlocking an invalid optimization.
The optimizer, AOT checker, fixed-width intrinsic checker, refined return
checker, and record-field checker consume the establishment fact rather than
trusting the static spelling.

Values reached through `any`, unknown foreign code, or unchecked gradual
mutation likewise carry no establishment fact. Checked calls must establish a
refined argument even when the callee is reached through a typed function
value. An unchecked Lua caller that violates a declared parameter type is
outside the checked-language contract, just as it is when passing a string to
a `number` parameter.

Module summaries transport the requirement and result facts without exposing
the compiler's internal dataflow representation. A bodyless declaration may
promise a refined result only at an explicit trust boundary, and AOT does not
consume that promise without the same validation policy used for other foreign
results.

## Conversions

### Widening

`float`, `int32`, and `uint32` widen to their declared supertypes implicitly and
without generated code. Arithmetic causes this widening because ordinary
operators still compute as LuaJIT numbers.

### Explicit value conversions

There is one establishing conversion for each value refinement:

```nupp
local f: float = nupp.math.f32.narrow(value)
local i: int32 = nupp.math.i32.wrap(integral)
local u: uint32 = nupp.math.u32.wrap(integral)
```

`f32.narrow(number): float` performs one binary32 store/load conversion without
canonicalizing NaN. It matches reified float storage and C `(float)` conversion.

`i32.wrap(integer): int32` and `u32.wrap(integer): uint32` use the released
32-bit modulo and signedness contracts. Requiring `integer` makes the caller
choose how a fractional, infinite, or NaN `number` becomes integral before the
fixed-width conversion.

The storage-only widths deliberately have no value conversion namespace. To
store one, assign to a physical slot. To compute, use `int32`, `uint32`, or
`integer`.

### Literals

Literals receive no implicit narrowing rule. They establish a refinement only
when their existing numeric value is already in its set:

```nupp
local half: float = 0.5       -- exact binary32 value
local tenth: float = 0.1      -- error; use f32.narrow
local byte: uint32 = 255      -- in range and integral
```

This follows the existing `integer` rule: an annotation checks the value; it is
not a hidden conversion. The explicit conversion is the one spelling for a
rounded decimal literal.

### Physical stores

Implicit narrowing occurs exactly where a store physically narrows. This
includes:

- a reified struct field;
- a fixed or variable C array element;
- a checked span element store;
- a `cdef` parameter.

The physical operation establishes the stored value. Requiring a source-level
conversion there would add text without changing the emitted instruction.

An ordinary function parameter, local, return, or table-backed field is not a
physical narrowing store. It requires an established value instead.

## Records and structs

A record field may use `float`, `int32`, or `uint32`. Construction and writes
must supply an established value, so the table stores an ordinary canonical Lua
number without generated conversion:

```nupp
local record Reading
    value: float
end

local reading = new Reading(value = nupp.math.f32.narrow(input))
reading.value = input                 -- error: number is not established float
reading.value = nupp.math.f32.narrow(input)
```

A struct field is a physical storage position and therefore accepts a wider
numeric source that its FFI store narrows:

```nupp
local struct Reading
    value: float
end

local reading = new Reading()
reading.value = input -- the float store establishes the loaded value
```

Identical-looking writes can therefore differ in whether they check. That is
intentional and is not container-scoped arithmetic: changing `struct` to
`record` produces a diagnostic rather than a different accepted answer. The
declarations already choose different representations; only the physical one
performs an implicit representation conversion.

Storage-only 8- and 16-bit fields are valid only on structs and C declarations,
not table-backed records.

## Functions and AOT boundaries

An ordinary refined parameter requires an established argument at every
checked call. Inside the body the parameter begins established. A refined
return similarly requires every returning path to produce an established value.

`@aot` adds no numeric rule. It consumes the same call-site fact:

```nupp
@aot
local function consume(scale: float): nil
end

consume(structValue.x)                 -- established load; valid
consume(nupp.math.f32.narrow(input))   -- established conversion; valid
consume(input as float)                -- assertion without fact; rejected
```

Because every accepted checked call establishes `scale`, the private AOT ABI
may use C `float`; the ordinary body receives the same binary32 value in an
AOT-disabled build. Removing `@aot` preserves the answer. A refined AOT
parameter may not silently choose a C `double` ABI merely because proof was
discarded, and the AOT wrapper may not round an argument that the ordinary body
would leave unchanged.

Static AOT-to-AOT calls transport the establishment fact directly. Calls
through typed function values apply the same argument check. Raw Lua and other
unchecked callers do not gain a semantic guarantee after violating the declared
parameter type.

## Arithmetic deliberately does not change

There is no binary numeric promotion. Every ordinary arithmetic operator over
these refinements yields `number`:

```nupp
local direct = particle.velocity * scale
local velocity = particle.velocity
local extracted = velocity * scale
```

`direct` and `extracted` are both binary64 `number` results. Container origin,
lexical position, and `@aot` play no part. Storing either result into reified
`float` storage performs the final narrowing.

The fixed-width namespaces remain the one explicit spelling for same-width
operations. Their checked signatures require established inputs and produce
established results. Their conservative Lua implementations continue to defend
gradual or unchecked runtime use.

The establishing operations are the exceptions to the input rule:

- `f32.narrow(number)` and canonicalizing `f32.round(number)` establish
  `float`;
- `i32.wrap(integer)` and `u32.wrap(integer)` establish their result types;
- `f32.fromBits(uint32)` establishes `float` from established bits.

Arithmetic, comparison, bit, shift, rotation, reinterpretation, and `fma`
members otherwise require established arguments of their declared refinement.
`f32.toBits` accepts established `float` and returns established `uint32`.

## NaN contract

The `float` refinement does not require one NaN payload. A reified load must not
test or rewrite NaN on every read, so every NaN produced by a binary32
store/load is a member of `float`.

`nupp.math.f32.narrow` follows the same non-canonicalizing conversion. The
already released `nupp.math.f32.round` keeps its stronger canonical-NaN
contract; it is an arithmetic operation rather than the refinement conversion,
and its result is an established `float`. `toBits` retains its released
canonical observation contract.

An optimization may not call noncanonical NaN input rounding an identity.
Eliminating a rounding requires establishment evidence plus proof that removing
any canonicalization is unobservable under the consuming intrinsic. This is a
contextual operation proof, not a type-only rewrite.

## Cost and optimization opportunities

The base refinement change adds no work to ordinary arithmetic or widening.
Physical stores already perform their conversions. Record fields require
established values instead of gaining hidden write-time conversions.

New runtime work appears only when source explicitly calls `f32.narrow`,
`i32.wrap`, or `u32.wrap`. Existing false annotations normally migrate to
`number`, preserving their generated Lua exactly. Source that intended the
fixed-width claim pays for the conversion it previously omitted.

The establishment analysis later enables measured optimizations:

- remove an intrinsic's input narrowing when established operands and its NaN
  contract prove the removal unobservable;
- reuse an established intrinsic result as the next intrinsic's input;
- merge only the final intrinsic result narrowing into an equivalent physical
  store.

Intermediate roundings in a chain of `f32` operations remain observable and do
not collapse into the final store.

A separate later AOT optimization may replace one binary64 operation over
binary32 inputs followed immediately by a binary32 store with a proved-identical
native float operation. It does not follow merely from the refinement. It needs
an operation-specific proof and differential coverage for overflow, subnormals,
signed zero, infinities, NaNs, target rounding, and contraction. Measurement
decides whether the additional lowering is worth retaining only after
correctness is established.

## Migration

Every source break is a diagnostic. No accepted program changes bits silently.

For an unestablished `float`, `int32`, or `uint32` value position, offer the
applicable complete fixes:

1. widen the annotation to `number` or `integer`, preserving current output;
2. insert the one explicit establishing conversion.

For an 8- or 16-bit name in a value position, replace it with `int32`, `uint32`,
or `integer` according to signedness and API intent. Those widths remain on the
physical storage declaration.

Migration covers source, fixtures, declaration files, reflected types, hover,
semantic tokens, module summaries, and generated reference examples in one
change. A diagnostic must not advertise a conversion that has not landed.

## Non-goals

- Operator promotion or per-operation rounding for ordinary operators.
- Parallel `f32`, `i32`, or `u32` type names.
- Arithmetic semantics scoped to structs, struct methods, or `@aot`.
- Boxing, scalar cdata wrappers, or metatable dispatch.
- Value-position `int8`, `int16`, `uint8`, or `uint16`.
- Incorporating boxed `int64` or `uint64` into the refinement tower.
- Changing `as` into a conversion.
- Treating a static refinement spelling as establishment evidence.

## Delivery

### R1: One coherent refinement release

Do not land the checker restriction before its final conversions and storage
projection exist. One release includes:

- the three value refinements and their establishment analysis;
- `f32.narrow`, `i32.wrap`, and `u32.wrap` with final contracts;
- storage-only narrow widths and the storage-to-value projection;
- physical-store assignment rules;
- record-field, parameter, return, literal, `as`, generic, and gradual rules;
- intrinsic signatures and establishment results;
- diagnostics, complete fixes, migration, LSP, reflection, summaries, reference
  generation, and semantic tests.

The release preserves generated output for every migrated site that widens to
`number` or `integer`. It adds runtime work only at written conversions and
existing physical stores.

### R2: Fact-driven intrinsic optimization

After R1 is stable, add establishment-aware elimination of redundant intrinsic
input work and final-store fusion. Keep the conservative runtime functions for
unchecked calls. Measure traced and interpreted paths before retaining each
rewrite, and test NaN behavior separately from finite arithmetic.

### R3: AOT consumption

Teach AOT IR and ABI lowering to consume establishment facts. Refined arguments
without facts are rejected before backend work; accepted `float` parameters may
use C `float`. Add the independently proved single-operation binary32
substitution only if its correctness and performance gates pass.

No delivery stage exposes a temporary conversion API, alternate numeric tower,
or checker rule scheduled for replacement by the next stage.
