# Type-level computation

Nupp can compute finite types while checking a program. This is a second,
type-checker-local reducer: it does not execute runtime code, invoke comptime,
generate declarations, or specialize function bodies.

## Members and mapped shapes

`keyof T` is the finite union of readable member keys; `writekeyof T` asks the
same question for writable members. `T.[K]` reads a member type and
`writeof T.[K]` gives the type accepted by a write. The dot is mandatory:
`T[16]` is a C array while `T.[16]` is member lookup.

```nupp
local type Events<T> = {
    readonly [K in keyof T as `${K}Changed`]:
        function(value: T.[K]): nil
}
```

Mapped shapes require `readonly` or `writeonly`. Their keys must reduce to a
finite union of string or integer literals. `as never` drops a key; remapping
two keys to the same name is an error.

## Const parameters

Const parameters admit only `string`, `boolean`, and exactly representable
`integer` values. They erase at runtime.

```nupp
local record Matrix<T, const Rows: integer, const Columns: integer>
    values: T[Rows * Columns]
end

local function field<const Name: string>(name: Name): `${Name}Field`
    return nil as any
end
```

Integer const expressions admit `+`, `-`, `*`, `//`, `%`, and comparisons.
Overflow, division by zero, conflicting literal inference, a dynamic argument,
and an unbound const parameter report at the type or call that needs the value.

## Match and templates

`match` tries arms in source order. `infer` names are scoped to one `then` arm.
A union is matched as one type unless `match each` explicitly distributes it.
An omitted `else` is `else never`.

```nupp
local type Element<T> =
    match T when {infer Item} then Item else T end

local type NonNil<T> =
    match each T when nil then never else T end

local type Parameter<Path> =
    match Path
    when `${infer _}:${infer Name}` then Name
    else never
    end
```

Initial structural patterns cover literals, ordinary types, arrays, tuples,
maps, function shapes (including `function(infer A...): infer R...`), pointers,
C arrays, readonly views, generic nominal applications, and templates.
Repeating an `infer` name requires the captured types or packs to be identical.
Template separators split bytes from left to right; adjacent inferred segments
are rejected as ambiguous.

A construction hole containing a finite string-literal union creates a
Cartesian product. One operation may produce at most 256 fields or template
members and visit at most 4096 reducer nodes.

Recursive aliases remain NUPP2115. Finite matching deliberately does not make
a type-level PEG or general parser evaluator: multi-segment parsing still needs
hand-unrolling, generated declarations, or a runtime parser.
