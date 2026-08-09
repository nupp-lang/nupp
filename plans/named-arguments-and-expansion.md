# Named arguments and value expansion

## Decision

Nupp adds named call arguments and declaration-directed value expansion.
Together they let a container occupy a function's positional prefix without
hiding that decomposition at the call site:

```nupp
local record Vec3
    x: number
    y: number
    z: number

    expands (x, y)
    expands (x, y, z)
end

local function draw(x: number, y: number, color: string?): nil
end

draw(...position, color = "red")
```

The call reserves `color`, so its positional prefix has two slots. The
arity-two expansion is selected and the generated Lua calls
`draw(position.x, position.y, "red")`.

`...value` is always an explicit request to expand. A plain `value` remains one
argument. Expansion is therefore never an implicit conversion.

## Named arguments

A named argument is `name = expression` inside parenthesized call arguments.
Named arguments must follow all positional arguments and expansions. They must
appear in parameter order; this keeps evaluation order identical in source and
generated Lua. Each parameter may be filled once. Unknown names, duplicates,
and a named argument overlapping the positional prefix are errors.

Omitted parameters continue to receive Lua's `nil`. When a later named
parameter follows an omitted optional parameter, generation inserts `nil` for
the gap.

Parameter names are retained on function types and are part of their static
call contract. This includes ordinary functions, function type annotations, C
declarations, constructors, methods, overload entries, and imported module
interfaces. A named call through a variable therefore behaves the same as a
direct call.

At runtime named arguments erase to ordinary positional arguments. They do not
allocate a table or require a dispatcher.

## Expansion declarations

`expands (field, ...)` is a compile-time member of a record, interface, or
struct declaration. Its arity is the number of listed fields. A declaration may
have at most one expansion of each arity. Every listed field must be readable,
and a field may appear only once in one expansion.

The expansion is an ordered field projection, not record iteration. Adding or
reordering unrelated fields cannot change it.

An expansion operand is required to be a stable value path: a local or other
name followed by zero or more ordinary dotted field accesses. This covers both
`...position` and flattened embedded values such as
`...entity.transform.position`. Calls, safe navigation, computed indexing, and
other producing expressions are rejected because lowering reads the path once
for every projected field. A later lowering IR may admit arbitrary expressions
by introducing a temporary without changing this design.

## Selection

Call checking first identifies the named suffix. For each callable candidate it
then enumerates the declared expansions of every explicit `...value`, retaining
the arrangements that:

1. do not overlap the first named parameter;
2. bind every argument to the candidate exactly once; and
3. satisfy the candidate's parameter pack.

Exactly one arrangement must survive. None is the ordinary rejected-call case;
more than one is an ambiguous call. The chosen expansion produces a single
adjusted argument pack before ownership and borrowing effects are applied.

Without named arguments, the callable's arity and parameter types perform the
same selection. A value with both two- and three-field expansions is therefore
legal at a call site only when exactly one fits.

## Interfaces and generics

Interfaces declare and inherit expansions as compile-time capabilities:

```nupp
local interface XY
    readonly x: number
    readonly y: number
    expands (x, y)
end

local interface XYZ is XY
    readonly z: number
    expands (x, y, z)
end
```

`XYZ` carries both arities. A record or struct declaring `is XYZ` inherits both
projections. Two parents may contribute the same arity only when their ordered
field lists are identical; conflicting projections make the declaration
invalid rather than changing behaviour according to the value's static view.

A bounded type parameter exposes its bound's expansions, so `T is XY` permits
`...value` wherever the arity-two projection is selected. A variable typed only
as `XY` cannot use the arity-three projection even when its runtime value is a
`Vec3`.

Generic nominal instantiations retain their declaration's projection names and
resolve the projected field types on the instantiated value. A union exposes an
expansion only when every member exposes the same ordered projection for that
arity. Conflicting intersection capabilities are rejected at their declaration
boundary.

## Overloads, methods, and ownership

Named labels and expansion arrangements participate in overload probing. There
is no best-match ranking: exactly one complete signature and arrangement must
survive. A method's implicit `self` is never nameable and does not count toward
the positional prefix.

Expansion reads fields. It cannot project a write-only member. The first
implementation also refuses affine projected fields: silently splitting an
owner would need partial-move state on the container, so callers pass such a
container explicitly until that state exists.

## Generation and tooling

Both constructs are erased:

```nupp
draw(...position, color = choose())
```

generates the equivalent positional Lua call:

```lua
draw(position.x, position.y, choose())
```

`expands` declarations generate no runtime member. Formatting preserves
`...value` without a space and formats named arguments with spaces around `=`.
The CST retains both constructs so LSP positions, diagnostics, and source
round-tripping remain exact.

## Deliberate constraints

- Named arguments are parenthesized-call syntax; Lua's string and table call
  sugar remains positional.
- Positional arguments never follow a named argument.
- Named arguments appear in declaration order.
- Expansion is explicit at both declaration and use sites.
- Expansion operands are names or dotted field paths; calls, safe navigation,
  computed indexing, and other producing expressions await temporary-aware
  lowering.
- Expansion fields are non-affine until the ownership model tracks partial
  moves of containers.
- There is no dot-count arity syntax. One `...` works for every pack size, and
  the call contract selects the unique valid declaration.
