# Type-level computation

Nupp can compute bounded types while checking a program. This is a second,
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

## Guarded recursive aliases

A generic alias may refer directly to itself beneath a `when` or `else` result.
The match must eventually select a result that does not recurse for the supplied
arguments. Unconditional recursion and mutually recursive aliases are rejected.

```nupp
local type Segment<Part> = match Part
    when `:${infer Name}` then {readonly [K in Name]: string}
    else {readonly [K in never]: string}
end

local type RouteParameters<Path> = match Path
    when `${infer Head}/${infer Tail}` then
        Segment<Head> & RouteParameters<Tail>
    else Segment<Path>
end

local type Params = RouteParameters<'users/:user/posts/:post'>
-- {readonly user: string} & {readonly post: string}
```

Recursive reduction is memoized by alias identity and canonical type, pack, and
const arguments. Identical active arguments report NUPP2133 immediately. A
request is also bounded to 128 recursive calls, 1024 alias reductions, 4096
term allocations, 256 result members, and the general 4096-node reduction
limit. Diagnostics include a bounded expansion trace, and the reducer polls a
cancellation control while it works.

This is enough for literal route parsing, nested-container normalization, and
similar structurally decreasing computations. It is not runtime parsing: the
input must be represented by a type or literal const argument, all types erase,
and a runtime parser or comptime value computation is still needed to produce
runtime data. Type-level PEG interpreters are possible only within the stated
budgets and are not a compatibility or performance target.

### Static PEG prototype

[`examples/static-string-peg.nupp`](../../examples/static-string-peg.nupp) is a
checked, deliberately small PEG interpreter. Its grammar is assembled from
types:

```nupp
-- command := ('get' name | 'set' name 'to' value) End
local type Get = Sequence<Token<'get'>, Capture<'name'>>
local type Set = Sequence<Token<'set'>,
    Sequence<Capture<'name'>,
        Sequence<Token<'to'>, Capture<'value'>>>>
local type Command = Sequence<Choice<Get, Set>, End>

local parsed: Parse<Command, 'set theme to dark'> = nil as any
local name: 'theme' = parsed.captures.name
local value: 'dark' = parsed.captures.value
```

The interpreter includes sequence, ordered choice with backtracking, named
one-token captures, greedy zero-or-more, and end-of-input. It uses a tagged
tuple machine so all transitions happen through one guarded recursive alias.
For clarity, input tokenization is only a split on single spaces. This is an
example of what the type reducer can express, not a runtime parser library or a
promise of LPeg-compatible syntax, diagnostics, or performance.

### Static `string.format` prototype

[`examples/static-format.nupp`](../../examples/static-format.nupp) uses the same
machinery to scan a literal format string into a heterogeneous argument tuple.
The checked tuple is expanded into the ordinary runtime function:

```nupp
local countArgs: FormatArguments<'%s has %d messages'> = args2('Ada', 3)
local count: string =
    string.format('%s has %d messages', unpack(countArgs))
```

A second reducer demonstrates literal result simplification for `%s` and `%%`:

```nupp
local exactPercent: Render0<'100%% ready'> = '100% ready'
local exactGreeting: Render1<'hello %s', 'Ada'> = 'hello Ada'
```

Those are exact static types. They do not replace the runtime call; conversions
that cannot be represented precisely widen to `string`.

Changing the second argument to a string reports the computed contract:

```text
NUPP2001: cannot initialize wrongType: {"Ada", "three"} is not a
{string, number}
```

Missing and surplus arguments likewise compare the supplied tuple with the
derived one. An unsupported directive remains visible in the result:

```text
NUPP2001: cannot initialize invalid: {"value"} is not a
{readonly formatError: "unsupported format directive %z"}
```

This prototype understands `%%`, `%s`, `%q`, and the ordinary numeric
conversion letters. It intentionally omits flags, width, precision, and more
than four arguments. The `args1` through `args4` helpers preserve heterogeneous
tuple slots because ordinary table literals infer homogeneous arrays.

The extra tuple binding is also a current implementation boundary: call
resolution does not yet normalize a recursive computed alias into a callable
signature. A production `string.format` contract could remove that ceremony by
normalizing before overload selection or by using a checker intrinsic backed by
the same format grammar. Type-level evaluation still would not replace the
runtime call or manufacture its result value.
