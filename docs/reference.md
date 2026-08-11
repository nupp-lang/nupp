# Nupp language reference

Every construct, the shortest program that uses it, and the diagnostic codes
that report getting it wrong. Generated from the compiler: `nupp reference`.

## Language

### The language

A gradually typed superset of LuaJIT's Lua dialect. Every valid LuaJIT program
is a valid Nupp program: a `.lua` file is required, built and run unchanged, and
the typed layer is refused in one (NUPP1006).

The extension says which floor a file is held to, so it is visible where the
file is rather than in a setting that governs everything at once:

    .nupp     strict    unknown variables and untyped exports are errors
    .g.nupp   gradual   the same typed syntax, without that floor
    .d.nupp   gradual   declares an interface somebody else implements
    .lua      gradual   plain Lua; the typed layer is refused

Write `.g.nupp` while a file is being typed and rename it to `.nupp` when it is
ready. The marker is not part of the module's name, so `models.g.nupp` is the
module `models` and nothing that requires it changes when it moves.
`nupp check --strict` holds every file to the floor whatever it is called, which
is how to see what a rename would cost.

Two things are not erased. A `struct` lowers to FFI cdata with a fixed layout,
and C headers import as checked declarations. Everything else is ordinary Lua at
run time.

Generated code targets LuaJIT 2.1.1784535649 or newer.

### Declaring things

A typed declaration says where it lives, the way an ordinary Lua definition
does: `local` keeps it to the file, a qualified name puts it on that table, and
`global` publishes it project-wide. Saying none of the three is refused rather
than defaulted, because plain Lua would have made the name a global and the same
silence is not reused for a different meaning.

Inside its own body a declaration answers to its simple name, so a recursive
field reads `User?` rather than `models.User?`.

```nupp
local models = {}

local type UserId = uint32
global type AppId = uint64

record models.User
    id: UserId
    name: string
    email: string?
end

return models
```

Reports: `NUPP2119`. `nupp explain <code>` says more.

### Types

Primitives: `any`, `unknown`, `never`, `nil`, `boolean`, `string`, `number`,
`integer`, `table`, `thread`, `userdata`. The C numeric tower: `float`,
`int8`…`int64`, `uint8`…`uint64`, plus `cdata`, `cstring` (`const char *`) and
`voidptr`.

`any` is gradual: compatible with everything, in both directions, silently.
`unknown` is its sound counterpart: everything fits into it, but it fits
nowhere else until narrowed or cast, the top of the type lattice. `never` is
the bottom: uninhabited, so it fits anywhere and nothing but itself fits it,
what a function that always raises, exits, or loops forever returns.

`table` is gradual the same way toward table structures only, and is what `{}`
infers as, so it drops out of a union already holding one: `opts = opts or {}`
leaves a declared record still holding its fields.

Postfix suffixes apply left to right: `T?` optional, `T*` pointer, `T[?]` a
variable-length C array and `T[N]` a fixed one. C arrays are zero-based cdata,
unlike the one-based `{T}`. `|` builds a union, a string literal is the type
containing just that value, and `const T` is a read-only view.

The fixed count may be an exact integer const expression. `T.[K]` is instead a
semantic member lookup; its mandatory dot keeps those two meanings separate.

Arithmetic on `integer` widens to `number`; annotate a result `number` unless
you have narrowed it back.

```nupp
local m = {}
local type Id = uint32
local type Maybe = string?
local type Either = string | integer
local type Mode = "read" | "write"
local type Counts = {[string]: integer}
local type Row = {integer}
local type Point = {x: integer, y: integer}
local type Handler = function(event: string): boolean
local type Reply = unknown
return m
```

Reports: `NUPP2101`, `NUPP2001`. `nupp explain <code>` says more.

### Functions

Parameters and results are annotated in the usual place. Several results are
listed comma-separated; inside a function *type* a multi-result needs
parentheses.

In a strict file, meaning `.nupp` or any file under `--strict`, an exported
function whose signature mentions `any` anywhere is treated as unannotated and
reported: `any` is the absence of a type, not a type. A function that returns
nothing still needs to say so, as `: nil`.

A function that always raises, exits, or loops forever returns `never`; a call
to it leaves the block it stands in, the way an inline `error` does.

```nupp
local m = {}

function m.add(a: integer, b: integer): integer
    return a + b
end

function m.split(text: string): string, integer
    return text, #text
end

function m.log(message: string): nil
    print(message)
end

function m.fail(message: string): never
    error(message)
end

return m
```

Reports: `NUPP2002`, `NUPP2106`. `nupp explain <code>` says more.

### Named and plucked arguments

Inside a parenthesized call, `name = value` fills that parameter directly.
Named arguments follow every positional argument and appear in parameter order.
They erase to ordinary positional Lua arguments; an omitted optional slot before
a later named argument is emitted as `nil`.

`name = *value` fills that parameter from the field of `value` the parameter
names: it means `name = value.name` and nothing more. `(a, b) = *value` fills
several parameters from one operand. Nothing is declared on the operand's type,
so a plucked name reaches any record with a field of that name, including one
the caller does not own. A name that is not a field of the operand is
**NUPP2004**; the resulting binding is checked like any other named argument, so
a field whose type does not fit its parameter is an ordinary rejected call.

A group's names are a set rather than a sequence. Every read is a field of one
path, so no order among them is observable and `(y, x)` binds exactly what
`(x, y)` does. Ordering is enforced between arguments, not inside a group.

A plucked operand is a name or dotted field path, such as `*entity.position`.
Bind calls, computed indexes, and other producing expressions to a local first;
that restriction is what lets the reads be unordered and evaluated once. A
statement-level call evaluates each dotted operand path and common prefix once,
while the projected fields remain direct positional arguments. A nested
expression instead repeats prefixes when needed; plucking never introduces a
closure or upvalue. Plucking is a named binding, so positional arguments cannot
follow it; a call keeps its several results only as the last argument, and so
fills the remaining positional slots only when nothing is plucked after it. This
applies to functions, callable records, methods, constructors, and specialized
calls with a statically known positional pack. A bounded type parameter plucks
through its bound, since the read is an ordinary field access. Safe statements and returns guard the optional
callee, receiver, and method before binding paths; nested safe calls retain the
native safe operator and its lazy argument evaluation.

```nupp
local record Vec3
    x: number
    y: number
    z: number
end

local record Entity
    position: Vec3
end

local function draw(x: number, y: number, color: string?): nil
    print(x, y, color)
end

local position = new Vec3(x = 1, y = 2, z = 3)
local entity = new Entity(position = position)
draw(x = *position, y = *position, color = "blue")
draw((x, y) = *entity.position, color = "blue")
draw(10, y = *position)

return position
```

Reports: `NUPP2004`, `NUPP2006`, `NUPP2125`. `nupp explain <code>` says more.

### Generics and bounds

Type parameters go in angle brackets after the name. `T is Bound` constrains
one, and the bound is an ordinary type, usually an interface. A `const Name:
string|boolean|integer` binder carries a compile-time-known value through a type
and erases from runtime code.

```nupp
local m = {}

interface m.Named
    name: string
end

function m.first<T>(xs: {T}): T?
    return xs[1]
end

function m.labelOf<T is m.Named>(value: T): string
    return value.name
end

return m
```

Reports: `NUPP2101`, `NUPP2131`. `nupp explain <code>` says more.

### Type-level computation

`keyof T` and `writekeyof T` enumerate readable and writable keys. `T.[K]` and
`writeof T.[K]` project their value types. A readonly or writeonly mapped shape
iterates finite literal keys and may remap them with `as`.

`match` selects the first decidable pattern; `match each` is the only form that
distributes over a union. `infer` bindings belong to one arm. Backtick template
types concatenate finite string literal sets and split literal strings at
unambiguous separators in a match pattern. Function patterns may capture their
parameter and result packs with `function(infer A...): infer R...`.

A final tuple pattern tail, `{infer Head, unpackof infer Tail}`, binds the fixed
prefix and remaining tuple. An empty `Tail` is `{never}`.

A generic alias may refer directly to itself beneath a match result. Reduction
is memoized and bounded; an unconditional reference, mutual recursion, an
identical active application, or an exhausted recursive budget is NUPP2133.

```nupp
local m = {}

local type Events<T> = {
    readonly [K in keyof T as `${K}Changed`]:
        function(value: T.[K]): nil
}

local type Element<T> =
    match T when {infer Item} then Item else T end

local type DeepElement<T> = match T
    when {infer Item} then DeepElement<Item>
    else T
end

local events: Events<{name: string}> = nil as any
local callback: function(value: string): nil = events.nameChanged
local element: Element<{integer}> = 1
local deep: DeepElement<{{integer}}> = 1
print(callback, element, deep)

return m
```

Reports: `NUPP2130`, `NUPP2132`, `NUPP2133`. `nupp explain <code>` says more.

### Type packs and variadic generics

`A...` declares a heterogeneous generic value sequence. A pack may have a fixed
head and a generic or homogeneous tail. `unpackof T` makes a computed tuple a
fixed tail, or a computed array a homogeneous tail, after generic inference and
type reduction. `{T,}` is a one-slot tuple; `{T}` remains an array. An
undecidable computed type stays gradual, while any other result is rejected.

This lets one declaration derive later parameters from an earlier literal:
`function<F is string>(format: F, ...: unpackof Arguments<F>)`. Under Lua's
ordinary value adjustment, only a final unparenthesized call or bare `...`
expands in an argument, assignment, or return list; parentheses project one
value. The explicit `...value` field projection described above is resolved
before that adjustment.

Inside a computed tuple, `{Head, unpackof Tail}` appends the tuple produced by
`Tail`; an array of `never` contributes no slots. `typeerror<Message>` carries a
deliberate failure out of a reducer. When `unpackof` needs that result, it
reports the authored message directly.

Whole-pack unions preserve relationships between results. This is why testing
the boolean returned by `pcall` narrows its sibling values to the callback's
results or the failure value together. Discarding an affine slot while adjusting
a list is an error.

```nupp
local m = {}

function m.forward<A...>(...: A...): A...
    return ...
end

function m.protected<A..., R...>(
    callback: function(A...): R...,
    ...: A...
): ((true, R...) | (false, any))
    return pcall(callback, ...)
end

return m
```

Reports: `NUPP2010`, `NUPP2121`, `NUPP2605`. `nupp explain <code>` says more.

### Property capabilities

`readonly` and `writeonly` grant member access independently on shapes,
interfaces, records, and indexers. A readonly property is covariant; a
writeonly property is contravariant. Declaring both separately permits
different types, while an unmodified property grants both capabilities at one
invariant type.

These are views of members. `const T` makes a whole value read-only, and
`borrows`/`exclusive` describe lifetime and aliasing instead.

```nupp
local m = {}

local type Input = {readonly value: string | integer}
local type Output = {writeonly value: string}

record m.Cell
    readonly value: string
    writeonly value: string | integer
    readonly [string]: string
    writeonly [string]: string | integer
end

function m.fill(out: Output): nil
    out.value = "ready"
end

function m.show(input: Input): string
    return tostring(input.value)
end

return m
```

Reports: `NUPP2001`, `NUPP2009`. `nupp explain <code>` says more.

### Intersections and overloads

`A & B` is the type of values satisfying both contracts. `&` binds more tightly
than `|`, nested intersections flatten, duplicate members disappear, and
`unknown` or gradual `any` add no constraint. Intersections compose structural
capabilities: readable member types intersect, writable member types unite, and
member names come from every constituent.

When every member is a function, the intersection is an overload set. The
checker adjusts the complete argument pack once, probes every candidate without
changing ownership or borrow state, and applies the selected signature only
when exactly one survives. There is no best-match ranking and source order does
not break a tie. The winner supplies its complete result pack, predicates,
`noreturn`, borrowing, ownership, and FFI output contracts.

A record may declare several constructors with distinct parameter packs.
`new T(...)` selects one with the same overload rule and emits a direct call to
that constructor's indexed runtime function; no dispatcher exists at run time.

Repeated method names likewise form an overload set without an annotation.
Each body remains a separate method entry. A colon call selects exactly one and
emits a direct call to its hidden runtime member; reading the overloaded method
as a field is **NUPP2126**, because there is no single Lua value to return.
Parameter packs must differ, because return types cannot select an entry.
`@override` replaces the exact matching interface-default entry, leaving other
overloads inherited. A bodyless interface may declare the operation as a
callable-intersection field; matching record bodies use the same slots without
`@override`, because no inherited body is being replaced.

See [Overloads and overrides](type-system/overloads.md) for worked examples of
method bodies, interface contracts, per-entry defaults, generics, constructors,
ambiguity, and dynamic facades.

```nupp
local type Named = {readonly name: string}
local type Counted = {readonly count: integer}
local type Entry = Named & Counted

local type Parse = function(text: string): integer
    & function(text: string, base: integer): string

local parse: Parse = nil as any
local decimal: integer = parse("10")
local hexadecimal: string = parse("10", 16)

local record Decoder
    function decode(self, text: string): string return "text:" .. text end
    function decode(self, value: integer): string return "integer:" .. tostring(value) end
end

local decoder = new Decoder()
local text: string = decoder:decode("source")
local number: string = decoder:decode(42)

return decimal, hexadecimal, text, number
```

Reports: `NUPP2124`, `NUPP2125`, `NUPP2126`, `NUPP2208`. `nupp explain <code>`
says more.

### Records

A record is a table with declared fields. An inline function is an instance
method when its first parameter is named `self`; without that parameter it is a
static function on the record's own table. Records are built with `new`.

`new` is how both records and structs are constructed, and the only way: it
lowers to the metatable stamp and the ctype call directly, installing nothing,
which is what leaves `__call` and `__new` to the program. Calling a record that
declares no `__call` contract is **NUPP2202**, and `new` on anything that is not
a record or a struct is **NUPP2206**.

The word is contextual, since a name has to follow it on the same line, so a
variable named `new` still means what it did.

A construction's values are its arguments: `new Point(x = 1, y = 2)`. The table
is the compiler's to build, so the instance is the only allocation and an
initializer table beside one is **NUPP2202**. Fields fill in written order, so
their values evaluate where the source put them. `new Point(1, 2)` fills them in
declaration order instead, builds the same table, and reports **NUPP2512**. A
struct has no such choice: it is its C layout, so `new Vec2(1.0, 2.0)` lowers to
`Vec2(1.0, 2.0)` with no table at any point, and naming its fields is
**NUPP2202**.

`local p: Point` declares storage and constructs nothing, so it holds nil until
something assigns to it and reading it before that is **NUPP2207**.

A declaration may state how it is built. A `constructor(self, ...)` body is what
`new T(...)` runs: the instance is made before it and returned after it, so the
body fills the fields in. It names that instance where a method names its
receiver, and no more passes it than a method does. It takes either spelling a
function takes anywhere else, so `constructor |self, at| -> do ... end` is the
same declaration; the expression form is refused, because what a constructor
hands back is settled before its body runs. Several constructors may declare
distinguishable parameter packs; the call selects exactly one and invokes it
directly. Every field that cannot hold nil has to be filled, and that guarantee
is the reason to prefer one, and it is why declaring a constructor closes the
direct form. A duplicate parameter pack, a missing receiver, or a body that
breaks either guarantee is **NUPP2208**. `constructor` is contextual, so a field
may still be called one.

The name is a value too: the runtime table `new` stamps on the instances it
builds. That table is their metatable, so it holds `metatable<Point>` rather
than `Point`, and the two do not stand for each other. The table may be passed
to `setmetatable` or have a metamethod contract installed on it, an instance may
not, and `Point is Point` is false without running. A function that wants a
declaration rather than one of its values takes `metatable<P>`.

One explicit type per field: grouped names are rejected.

```nupp
local m = {}

--- A point in the plane.
record m.Point
    x: integer
    y: integer

    --- Its distance from the origin, squared.
    function lengthSquared(self): number
        return self.x * self.x + self.y * self.y
    end
end

--- A point on a line through the origin.
record m.Diagonal
    x: integer
    y: integer

    constructor(self, at: integer)
        self.x = at
        self.y = at
    end
end

local corner = new m.Diagonal(3)
local origin = new m.Point(x = 0, y = 0)
print(corner.x, origin:lengthSquared())

return m
```

Reports: `NUPP2004`, `NUPP2118`, `NUPP2202`, `NUPP2206`, `NUPP2207`, `NUPP2208`.
`nupp explain <code>` says more.

### Interfaces

An interface declares a shape without a body. `record X is Y` states that X
includes Y, and the checker holds it to that.

```nupp
local m = {}

interface m.Named
    name: string
end

record m.User is m.Named
    name: string
    id: uint32
end

return m
```

Reports: `NUPP2001`. `nupp explain <code>` says more.

### Default implementations

An interface may implement what it declares, and a declaration that takes the
contract takes the behaviour with it. The body is emitted once and referenced,
so an implementor inherits the behavior rather than a copy, resolved where it
is written rather than looked up at run time.

This is the one thing that gives an interface a runtime presence: one that
declares only signatures still emits nothing.

`@override` is required on a member replacing an inherited default, and is an
error on one replacing nothing. Two interfaces providing the same name are two
implementations and no reason to prefer either, so the declaration writes the
member itself to say which behaviour it means. Both are **NUPP2118**.

```nupp
local m = {}

interface m.Greeter
    name: string

    function greet(self): string
        return "hello, " .. self.name
    end
end

record m.Person is m.Greeter
    name: string
end

record m.Shouter is m.Greeter
    name: string

    @override
    function greet(self): string
        return "HELLO"
    end
end

return m
```

Reports: `NUPP2118`. `nupp explain <code>` says more.

### Associated types

An interface may state a type it does not name. Whatever takes the contract
names it, and the name is reached through whatever answered it: `T.Item` on a
type parameter, `Lines.Item` on a declaration, `self.Item` inside a body.

Where it is written says what it means. On an interface, `associated type Item`
states a requirement and `is Bound` says what may answer; `= T` states a
**default** an implementor may replace, and `== T` **fixes** the type so every
implementor answers exactly it. Anywhere else, `= T` answers -- `==` is refused
there, because a concrete declaration already answers exactly.

That difference is what a value's type can rely on. A default stays **opaque**
through an interface-typed value, since an implementor may answer otherwise; a
fixed equality resolves through the interface itself. A default is copied to
each concrete implementor, with `self` rebound there, so `associated type Value
= self` reads as that implementor.

An interface carrying associated requirements is nominal at that part: a
structural value has nowhere to put an answer, so it is not one of these however
many fields it has. An opaque projection fits its effective bound and exposes
that bound's members -- read as the projection, so a `self`-returning member
answers `T.Item` -- while the bound does not fit the projection. Through an
intersection the requirements coalesce and their bounds intersect; through a
union every alternative has to state the name, the bounds unite, and the answers
distribute.

Associated types are not nested `type` aliases: an alias is lexically scoped,
reachable by path, and not inherited. They have no runtime representation at
all, so a projection is only legal where a C layout is needed once it resolves
concretely, an interface leaving one unsettled cannot carry `satisfies` -- `==
any` is fixed and still settles nothing -- and an answer whose head inference
never reached is checked as `any` and reported by `gradual-projection`.

```nupp
local m = {}

interface m.Component
    componentId: integer
    associated type Value = self
end

interface m.ScalarComponent<E> is m.Component
    componentId: integer
    associated type Value == E
end

record m.Position is m.Component
    componentId: integer
    x: number
end

record m.Archetype
    function column<C is m.Component>(self, component: C): {C.Value}
        return nil as any
    end
end

local archetype = new m.Archetype()
local health: m.ScalarComponent<number> = nil as any
local position = new m.Position(componentId = 1, x = 0)

local raw: {number} = archetype:column(health)
local held: {m.Position} = archetype:column(position)

return m, raw, held
```

Reports: `NUPP2127`, `NUPP2128`, `NUPP2129`, `NUPP2134`, `NUPP2135`. `nupp
explain <code>` says more.

### Refinements

An interface may carry a `satisfies` declaration, which names the runtime test
that decides whether a value is one of these. `x is T` compiles to it, so
`s is m.Circle` below becomes `type(s) == "table" and s.kind == "circle"`.

It is a function of the value, so it is written as one, in either spelling a
function takes anywhere else: `satisfies |self| -> test`, or `satisfies(self):
boolean ... end` whose body is the one `return` saying the same thing.

Only an interface. A record is identified by the metatable `new` stamps and a
struct by its ctype, so both already answer `is` exactly; a refinement beside
either would be a second answer to a settled question. An interface has no
runtime table at all, so this is the only identity it can have, and it is what
lets a value this program did not build, a table off a decoder or anything an
untyped library returned, answer `is` at all.

The test runs wherever `is` is written, so it reads the declaration's own fields
through `self` and nothing else: comparisons against literals, `type()` tests,
and `and`/`or`/`not`. A call, arithmetic, an outside name, a refinement that
always answers the same way, or one on a record or struct is **NUPP2122**, as
is a declaration whose own fields provably fail an interface it declares.

```nupp
local m = {}

interface m.Shape
    kind: string
end

interface m.Circle is m.Shape
    kind: string
    radius: number

    satisfies |self| -> self.kind == "circle"
end

function m.area(s: m.Shape): number
    if s is m.Circle then return 3 * s.radius * s.radius end
    return 0
end

return m
```

Reports: `NUPP2122`. `nupp explain <code>` says more.

### Structs

A `struct` reifies: it lowers to `ffi.typeof`, so it has a fixed layout and no
hash lookup per field. `T[?]` and `T[N]` give contiguous arrays of them. This is
the one place a type changes what the program does at run time rather than only
what the checker accepts.

Fields are what fits in C memory: the numeric types, `boolean`, another struct
by value, a pointer, and a fixed array `T[N]`, which sits inline as N elements
of the struct's own bytes. A `T[?]` field is refused, because a struct whose
size depends on a count nobody wrote has none. A GC-managed type is refused too,
so a `string` field means this wants to be a `record`; that is **NUPP2201**.

A struct may point at itself, which is how a linked structure is written. By
value it cannot: that would have no size.

`layoutof(T)` answers how one is laid out, with the fields in declaration order
with their C types, offsets, sizes and padding, the struct's size, and a
fingerprint over all of it. Reifying puts a value where nothing that walks a
table can reach it, and this is what reaches it again without the language
choosing a serialization format.

```nupp
local m = {}

struct m.Vec3
    x: float
    y: float
    z: float
end

--- A fixed array sits inline; a pointer to this declaration links one to the next.
struct m.Vertex
    pos: float[3]
    uv: float[2]
    next: m.Vertex*?
end

local type Buffer = m.Vec3[?]
local type Fixed = m.Vec3[16]

local vertex = new m.Vertex()
vertex.pos[0] = 1.5

local layout = layoutof(m.Vertex)
print(layout.size, layout.fingerprint)
for _, field in ipairs(layout.fields) do
    print(field.name, field.ctype, field.offset, field.size, field.padding)
end

return m
```

Reports: `NUPP2203`. `nupp explain <code>` says more.

### Literal and tagged unions

A union of string literals is a closed set of values, which is what other
languages spell `enum`. It erases: the value at run time is the plain string,
and a bare literal lands in it. A dispatch over one that leaves members
unhandled is reported, which is what makes adding a member a compile-time task
list rather than a run-time surprise.

A union of records, each carrying a literal-typed field, is a tagged union:
the field is the tag, and comparing it narrows the union to the one record
that declares that tag. That is the form to reach for when the alternatives
carry data, since a bare literal carries none.

```nupp
local m = {}

type m.Color = "red" | "green" | "blue"

function m.describe(c: m.Color): string
    if c == "red" then return "warm"
    elseif c == "green" then return "cool"
    else return "cool" end
end

record m.Circle
    kind: "circle"
    radius: number
end

record m.Square
    kind: "square"
    side: number
end

type m.Shape = m.Circle | m.Square

function m.area(shape: m.Shape): number
    if shape.kind == "circle" then
        return 3.14159 * shape.radius * shape.radius
    end
    return shape.side * shape.side
end

return m
```

Reports: `NUPP2107`. `nupp explain <code>` says more.

### Narrowing

`e is T` tests a type and narrows in the branch it proves. A truthiness test
narrows an optional, including through a field path copied into a local. `e as
T` is an explicit cast where you know better than the checker.

A function may return a predicate, `p is T`, meaning it answers whether that
parameter holds the type. The value returned is a boolean, and the caller
narrows on it.

```nupp
local m = {}

local function isString(v: any): v is string
    return type(v) == "string"
end

function m.describe(value: string | integer): string
    if isString(value) then
        return "text of " .. #value .. " bytes"
    end
    return "number " .. value
end

function m.nameOf(user: {name: string?}): string
    local name = user.name
    if not name then return "anonymous" end
    return name
end

return m
```

Reports: `NUPP2001`. `nupp explain <code>` says more.

### Owned resources

`@owned(cleanup)` says a result carries a cleanup obligation. An ordinary local
with known cleanup is destroyed automatically at its lexical scope boundary.
Dropping it, passing it to a `takes` parameter, returning it as an owner, or
converting it with `intoRaw` ends or transfers that responsibility exactly once.
An opaque or otherwise unresolved owner still requires an explicit terminal;
forgetting that choice is a compile error, not a leak.

Parameter modes say what a call does with what it is given: `takes` consumes,
`borrows` does not (and the borrow cannot escape), `exclusive` borrows with no
other view live, and `retains`/`releases` describe C holding a pointer across a
call.

`T preserves value` on a result transports the exact capability of that
parameter through scalar generic narrowing. `T borrows (source)` ties a result,
or a nominal record field, to its named root. A `scoped` callback parameter may
capture borrows only because its callee proves that callback cannot escape.
`@owned(cleanup)` may decorate a function-valued record or interface field so a
bodyless API can declare a fresh owning result without a wrapper.

Affine nominal fields have path-sensitive live/moved state. A `ResourceSet`
from `nupp.resource_set` is the checked escape hatch for a dynamic number of
owners, and `nupp.span` supplies rooted, bounds-checked byte views. Raw or
unknown coroutine suspension still cannot cross an obligation; checked handled
suspension may do so only through its cancellation contract.

Lifetime alone does not prove a C pointer index is in bounds. Direct pointer or
variable-length C-array indexing therefore requires `unsafe`; use `nupp.span`
when a runtime count is available. A fixed C array rejects a statically
out-of-range literal and inserts a runtime guard for a non-literal index.

The ownership intrinsics live under the always-available `nupp` global:
`nupp.drop`, `nupp.borrow`, `nupp.intoRaw`, `nupp.fromRaw`,
`nupp.borrowFrom`, and `nupp.pin`. The old bare spellings remain aliases and
lower identically. Either spelling is shadowed by a binding of that name,
`nupp` included.

```nupp
local m = {}

local function closeFile(file: LuaFile)
    file:close()
end

--- Opens a file the caller must discharge.
---
--- @param path where to read from
--- @return an owned handle
--- @raises when the file cannot be opened
@owned(closeFile)
function m.open(path: string): LuaFile
    local file = io.open(path, "r")
    if not file then error("cannot open " .. path) end
    return file
end

function m.slurp(path: string): string
    do
        local file = m.open(path)
        return file:read("*a")
    end
end

return m
```

Reports: `NUPP2603`, `NUPP2615`. `nupp explain <code>` says more.

### C interop

`cdef function` and `cdef struct` declare C with checked signatures. `from
"lib"` resolves through `ffi.load`; omitting it uses the default namespace.

`cheader('path.h')` types a pinned header at compile time. The compiler hands it
to its own `ffi.cdef` and reads the declarations back through `ffi.typeinfo`, so
LuaJIT's C parser is the source of truth and the sizes are this platform's. No
generated file, and no C compiler for a self-contained header. `nupp import-c`
ejects a committed, hand-editable binding module instead.

Reconstructing a raw pointer is confined to `unsafe do` blocks.

```nupp
local m = {}

cdef struct Point
    x: float
    y: float
end

cdef function labs(n: int32): int32

function m.magnitude(n: int32): int32
    return labs(n)
end

return m
```

Reports: `NUPP2203`, `NUPP2101`. `nupp explain <code>` says more.

### Annotations

An annotation is declared as a record or struct carrying `@annotation`, whose
`targets` list says where it may be applied. Its fields are the annotation's
members, and values are compile-time constants. Unknown annotations, wrong
targets and wrong value types are errors, so an annotation never becomes a
silently erased comment.

Applications spell an unqualified `@name`, so a definition is registered
project-wide and is the one declaration exempt from the visibility rule. Both
the definition and every application are erased from the generated Lua.

Built-in contracts use the same surface. `@effects` is a complete effect
summary: visible bodies are checked against it and bodyless declarations are
trusted. `const` is the shallow identity promise for a bodyless binding in a
`.d.nupp`; it does not freeze a table's fields. `@relax` records a closed set
of observable guarantees an optimization may change, locally to one function.

```nupp
local m = {}

@annotation(targets = {"record", "struct"})
record serializable
    format: string
    version: integer?
end

@serializable(format = "json")
record m.User
    id: uint32
end

return m
```

Reports: `NUPP2119`. `nupp explain <code>` says more.

### Declaration derives

`@derive(Debug, Default, From, JSON)` adds checked members to one record without
source splicing. The providers add `debug`, static `default`, single-field
`from`, and `toJSON`/`fromJSON`/`fieldCodec`; `nupp.default` and `nupp.into`
infer through the static factories. `@default`, `@debug`, and `@json` configure
fields. Generated members participate in lookup and conformance and conflict
with written members. Derive augments a declaration; comptime produces values.

Reports: `NUPP2801`, `NUPP2802`, `NUPP2803`, `NUPP2804`, `NUPP2805`, `NUPP2806`,
`NUPP2807`, `NUPP2808`. `nupp explain <code>` says more.

### Docblocks

A leading `@!internal` inner annotation keeps a file out of public generated
documentation. On `init.nupp`, it also hides every descendant module; private
documentation builds include the complete tree.

An adjacent `---` run documents the declaration under it. `@param`, `@return`,
`@field`, `@typearg`, `@local`, `@internal` and `@export` are understood. An
`@internal` declaration stays out of public output but remains in private
documentation builds. `nupp doc` renders them.

`@raises` says what makes a function raise, one line per condition. It is the
one docblock tag the checker reads as well as renders: a documented function
that calls `error` without one is `undocumented-raise`. Raising is part of how a
function is called, and Lua has no signature to find it out from.

```nupp
local m = {}

--- Reads a configuration file.
---
--- @param path where to read from
--- @return the file's contents
--- @raises when the file cannot be read
function m.load(path: string): string
    local file = io.open(path, "r")
    if not file then error("no such file: " .. path) end
    return file:read("*a")
end

return m
```

Reports: `NUPP2506`. `nupp explain <code>` says more.

### Modules

Modules are Lua's: a file returns a value and `require` gets it. A module's type
is whatever the file returned, and a declaration with a runtime value puts
itself on that table, so nothing is merged in behind your back. Another file
reaches a member through the module it was attached to, and a module path also
names a type directly, as in `models.user.User`.

The returned local already identifies the module table; there is no `module`
keyword. Use `const M.field = value` to make an export slot immutable. A fresh
table can mark individual named slots with `const name = value`, or use
`const... M.field = {...}` to mark all of its named slots recursively. These
guarantees are checked in Nupp and preserve exact primitive literals for
constant propagation in consumers.

A `.d.nupp` declaration file is the exception: it describes an interface it does
not own and returns no table, so a bare declaration there is that interface.

`models.nupp`:

```nupp
local models = {}

record models.User
    id: uint32
    name: string
end

return models
```

```nupp
local models = require("models")

local user: models.User = new models.User(id = 1, name = "ada")

return user
```

Reports: `NUPP2120`, `NUPP2101`. `nupp explain <code>` says more.

### LuaJIT 3.0 syntax

Nupp implements every LuaJIT 3.0 syntax extension and adds to them. Most is
written straight through to the output, because LuaJIT 2.1 backported it.

Available: `continue`; compound assignment (`+= -= *= /= //= %= &= |=`); the
ternary `c ? a : b`; `??` for nil-coalescing; safe navigation `?.`; short
functions `|x| -> e`; `const` bindings including `const function` and immutable
named table fields; and the customary spellings `!`, `&&`, `||`, `!=`.

`const M.field = value` initializes an immutable field. Inside a fresh table
constructor, `const name = value` does the same for a named slot. `const...`
before the outer field declaration is sugar that applies it recursively to the
new table graph:

```nupp
local M = {}
const... M.settings = {name = "nupp", nested = {count = 0}}
return M
```

The checker rejects later writes through those paths. Plain `const M.field`
remains shallow: ordinary inner fields stay mutable unless they are themselves
declared `const`.

The customary spellings are legal but linted: `not`, `and`, `or` and `~=` are
the ones Lua already has, and two spellings of one thing drift apart across a
codebase. Suppress per statement with `@allow("customary-operator")`.

```nupp
local m = {}

function m.demo(n: integer, flag: boolean, label: string?): integer
    local total = n
    total += 1
    local shown = flag ? "on" : "off"
    local name = label ?? "anonymous"
    for i = 1, 10 do
        if i == 5 then continue end
        total += i
    end
    local double = |x: integer| -> x * 2
    return total + #shown + #name + double(2)
end

return m
```

Reports: `NUPP2504`. `nupp explain <code>` says more.

### Lints and suppression

A type error says the program does not mean what it says it means: nothing
configures or silences it. A lint says the program means something you probably
did not intend, so it has a name, a level a project can move, and a suppression
a statement can apply.

`@allow` takes lint names or codes, applies to the statement it decorates and
nothing beyond it, and reaches any lint at any level. Bare `@allow` silences
every lint on that statement. It does not reach a type error; naming one is
NUPP2108.

Levels are set in `nupp.lua` under `lints`, by name or by category, resolving
registry default → category → name → `@allow`.

```nupp
local m = {}

function m.toggle(flag: boolean): boolean
    @allow("customary-operator")
    local inverted = !flag
    return inverted
end

return m
```

Reports: `NUPP2108`. `nupp explain <code>` says more.

### Suspension regions

`nosuspend do ... end` refuses, while compiling, any call inside it that may
suspend the current coroutine. It is lexical and static: it erases to an
ordinary `do` block and has no run-time component at all.

Whether a function may suspend is already inferred, since `coroutine.yield` sets
it and it propagates through the call graph, and it travels across a module
boundary on the function's type, so an export, an alias, and a local are all
answered the same way. A callee nothing resolved is refused, because a region
exists to be careful about exactly that.

**NUPP2701** names the call and the path from it to the suspension, since a
refusal is not actionable when the yield is four functions away.

For anything whose body this compiler never sees, such as a declared host
binding, a C function, a parameter or a callback, the guarantee is written in
the type:

    nosuspend function(x: number): integer

That is a positive guarantee, so an unmarked function type stays conservatively
may-yield and silence is never mistaken for a promise. It is an ordinary part of
the type, so it takes part in identity, subtyping, aliasing and substitution: a
`nosuspend function` fits an ordinary slot, an ordinary function does not fit a
`nosuspend` one, and an alias of either keeps what it had. The pure standard
library is declared this way rather than special-cased, which is why
`math.floor` is admitted and `print` is not.

`nosuspend` guarantees that control cannot be suspended. It does not guarantee
that a callback is effect-free, or that calling one is legal across a C
boundary: `table.sort` and `string.gsub` cannot suspend their caller and are
declared `nosuspend` for that reason, while a comparator or a replacement that
yields fails at the C-call boundary instead. That is a different diagnostic
about a different fact.

`nosuspend` opens a region when `do` follows it and qualifies a type when
`function` does; elsewhere it is an ordinary name.

```nupp
local m = {}

local function total(values: {integer}): number
    local sum = 0
    for index = 1, #values do
        sum = sum + values[index]
    end

    return sum
end

function m.commit(values: {integer}, report: nosuspend function(n: number): nil): number
    local answer = 0
    nosuspend do
        answer = total(values)
        report(answer)
    end

    return answer
end

return m
```

Reports: `NUPP2701`. `nupp explain <code>` says more.

### Comptime

`comptime do ... end` is an expression whose value is computed while the file is
compiled. The block is ordinary Nupp, and what it returns is written into the
generated Lua as a literal, so nothing of the work survives into the program.
`comptime` opens a block only when `do` follows it on the same line; everywhere
else it is an ordinary name.

Its reason to exist is the loop that accumulates: a table built by iterating,
which no rewrite of an expression can produce. A constant expression does not
need it, because `-O1` already folds one.

A block returns exactly one value, and that value is checked where it lands, so
a result that does not fit its declared type is the ordinary error it would be
if you had typed the literal out. Quotable results are nil, booleans, numbers
that read back unchanged, strings, and acyclic tables of those with no
metatable. A table reachable by two paths is **NUPP2413** rather than two
tables; NaN and the infinities have no literal spelling.

A sealed compiler provider may instead return an opaque description that has no
literal spelling. It materializes only when the block directly initializes a
declaration with an explicit provider-owned runtime type. An inferred binding or
opaque value hidden in an ordinary table is **NUPP2414**. A declared type for
which the opaque result has no registered materialization relation, or a worker
payload that fails the provider's schema and fingerprint checks, is
**NUPP2415**. A finalized blueprint or generated runtime expression over its
provider limit is **NUPP2416**. Providers return a closed structured expression;
they cannot return source, declarations, imports, or references to source
bindings.

A block reads only its own locals and the compile-time environment. A runtime
local, an upvalue, module state, or a global is **NUPP2410**, and it may not
write to one either. The environment is an allowlist: `assert`, `error`,
`ipairs`, `pairs`, `select`, `tonumber`, `tostring`, `type`, and named members
of `math`, `string`, `table` and `bit`. A member the allowlist leaves out is
**NUPP2411** and says which. There is no `io`, `os`, `require`, `ffi`, `debug`,
`load`, clock, or randomness.

Determinism excludes platform-varying libm functions and table-address
`tostring`; `pairs` is sorted. Evaluation runs in an isolated, cancellable
worker with step, call-depth, time, memory, result, and protocol limits, so a
crash or oversized result fails only that block.

File-private `@comptime` helpers are normally typed, share the caller's budgets,
may inspect `TypeInfo`, and erase from runtime output. They are callable only by
comptime code and are not yet generic, variadic, or cross-module.

Comptime produces data, never declarations or source. `nupp build --json`
reports materialization identities, fingerprints, sizes, runtime features, and
ABI versions; manifest caches retain the canonical blueprint and lowering.

```nupp
local m = {}

@comptime local function step(acc: integer): integer
    return acc & 1 ~= 0 and 0xedb88320 ~ (acc >> 1) or acc >> 1
end

const CRC32 = comptime do
    const entries = {}
    for byte = 0, 255 do
        local acc = byte
        for _ = 1, 8 do
            acc = step(acc)
        end
        entries[byte + 1] = acc
    end
    return entries
end

function m.checksum(text: string): integer
    local acc = 0xffffffff
    for index = 1, #text do
        acc = CRC32[((acc ~ text:byte(index)) & 0xff) + 1] ~ (acc >> 8)
    end
    return acc ~ 0xffffffff
end

return m
```

Reports: `NUPP2410`, `NUPP2411`, `NUPP2412`, `NUPP2413`, `NUPP2414`, `NUPP2415`,
`NUPP2416`, `NUPP2419`. `nupp explain <code>` says more.

### PEG matchers

`nupp.peg.compile(grammar, options?)` compiles LPeg-re-style byte grammar text
at either phase into a pure-Lua matcher with no LPeg dependency. In `comptime`,
its opaque blueprint's capture shape supplies `nupp.peg.Peg<R...>` when
unannotated. A literal runtime grammar infers the same type; a dynamic string
returns `Peg<...any>`. `Peg<R...>` satisfies `Matcher<R...>`, so a generic
adapter can return `((R...) | (nil))`. `Backend`, `Definitions`, and
`CompileOptions` are also direct types on `nupp.peg`; `Action` and `Actions` are
deprecated aliases for older Nupp sources.

`peg(subject, init)` and `peg:match(subject, init)` are equivalent. A recognizer
returns the next 1-based byte position or nil. `init` defaults to 1 and may be
negative; matching is unanchored unless the grammar ends in `!.`. `isMatch`
searches for a boolean result, while `find` returns the half-open `first, next`
range followed by the result pack. Both include the empty position after the
final byte.

`forEachMatch` visits every non-overlapping `first, next, R...` result.
`replace` changes the first match and `replaceAll` changes each one, using
either literal text or a callback returning text. Empty matches advance one byte
so iteration and replacement cannot stall. None of these operations allocates
match records or result tuples; see `docs/peg.md` for the complete contracts.

### Writing expressions

The notation is byte-oriented. Whitespace is ignored between expressions and
`--` comments run to the end of their line. Its precedence from tightest to
loosest is primary expressions, suffixes, predicates, sequence, then ordered
choice.

```
 Form                  Meaning
 ────────────────────  ─────────────────────────────────────────────────────
 'text', "text"        exact literal bytes
 .                     any one byte
 [a-z_], [^0-9]        one byte inside or outside a class
 %a, %d, %s, %w, %x    ASCII letter, digit, space, alphanumeric, or hex byte
 %name                 pattern supplied by CompileOptions.definitions
 p q                   sequence
 p / q                 ordered choice, trying p before q
 p?, p*, p+            optional, zero or more, or one or more
 p^n, p^+n, p^-n       exactly, at least, or at most n repetitions
 &p, !p                positive or negative predicate without consumption
 { p }                 substring capture
 {}                    current byte-position capture
 {| p |}               collect the captures made by p into an array
 {: name: p :}         group captures under name, which is optional
 {~ p ~}               substitution capture
 =name                 match the text in named group name
 p -> {}               collect captures into a table
 p -> n, p -> 'text'   select capture n, or format captures into text
 p -> name             transform captures through definition name
 p => name             match-time definition name
 p >> name, p ~> name  accumulator and fold definitions
 name <- p             rule definition; the first rule is the start rule
 name, <name>          rule reference inside a grammar
 !.                    end-of-input assertion
```

Quoted strings contain literal bytes and do not process backslash escapes. A
class may contain ranges and predefined classes. The long predefined names are
`%alpha`, `%cntrl`, `%digit`, `%graph`, `%lower`, `%nl`, `%punct`, `%space`,
`%upper`, `%alnum`, and `%xdigit`; an uppercase one-letter form such as `%D`
means the complement of its lowercase class.

PEG choice is ordered rather than symmetric. Put a longer literal before its
prefix: `'integer' / 'in'`, not `'in' / 'integer'`. Repetition is possessive
and its body must consume input whenever it succeeds, so nullable expressions
such as `('')*` are rejected. Parentheses group an expression before a suffix
or make precedence explicit.

### Captures and definitions

A capture `{ p }` returns its matched substring, `{}` returns the current byte
position, and `{| p |}` or `p -> {}` makes several captures one explicit table
result. Named groups assign table fields, substitution captures rewrite their
matched substring, and `=name` matches a prior named capture. Nupp matchers have
one top-level result; wrap multiple or repeated captures in a table. Every
ordinary ordered-choice arm must have the same capture shape.

`p -> name` is an ordinary transformation and is deferred until the complete
match succeeds, so discarded PEG alternatives cannot cause user-code side
effects. `p => name` is a true LPeg match-time capture: its function receives
the subject and current position, may inspect captures, and returns the next
position plus new captures. `>>` accumulates and `~>` folds captures. `%name`
obtains an external pattern. Runtime values live in `{definitions = values}`. A
static grammar instead materializes as a factory whose closed parameter record
contains exactly the referenced names.

### Rules and validation

Recursive grammars use `name <- p` definitions and `name` or `<name>`
references. Every reference must resolve, repetitions may not contain a
nullable expression, ordered-choice capture shapes must agree, and left
recursion is rejected. Those invalid grammars are **NUPP2417** while the common
materialization boundary and size diagnostics remain **NUPP2414** through
**NUPP2416**.

### Compilation and backends

Both phases produce one validated canonical program and matcher shell.
Recognition and simple captures lower to bytecode. The default `auto` backend
generates and caches Lua match, search, traversal, and safe literal replacement
functions from it. Common shapes become straight-line functions; other ordinary
grammars use an opcode-specialized dispatch loop. Stateful LPeg captures retain
the canonical capture graph and use its executor.

`{backend = "vm"}` interprets bytecode without `loadstring`, which suits cold
grammars and restricted hosts. Stateful captures use the same graph executor in
either mode. Runtime parsing, programs, and generation are cached by grammar and
backend. Runtime definition values use
`{definitions = values}`; static definitions remain factory inputs. The
expression syntax is LPeg 1.1 `re`; `docs/peg.md` documents native result packs
and explicit table captures.

```nupp
local m = {}

const Identifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile([[
        [a-zA-Z_] [a-zA-Z_0-9]* !.
    ]])
end

const Fields: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile([[
        {| { [a-z]+ } (',' { [a-z]+ })* |} !.
    ]])
end

function m.identifier(text: string): integer?
    return Identifier(text)
end

function m.matcher(grammar: string): nupp.peg.Peg<...any>
    return nupp.peg.compile(grammar)
end

function m.fields(text: string): {string}?
    return Fields(text)
end

return m
```

Reports: `NUPP2414`, `NUPP2415`, `NUPP2416`, `NUPP2417`. `nupp explain <code>`
says more.

### Semantic reflection and field codecs

`nupp.reflect(T)` resolves `T` in a type position and creates an immutable,
target-independent semantic descriptor for comptime. Schema 2 represents the
possibly recursive type as an acyclic indexed graph: `root` selects a node in
`types`, and edges between nodes are integer indices. The graph covers nominal
records, interfaces and structs; shapes, fields and indexers; function
signatures and packs; generic arguments; unions and intersections; ownership
wrappers; arrays, pointers and C types. Checked typed annotations on
declarations and fields appear as ordered `annotations`; an `@ref` argument is
an edge into the same `types` graph. The root's common fields are also available
directly as `kind`, `name`, `fields`, `annotations`, and `fingerprint`.

User comptime code may read descriptor members, use `#`, and traverse arrays
with deterministic `ipairs` or `pairs`. Views preserve identity for equality
but reject mutation and cannot escape as runtime tables. The fingerprint is
computed from the canonical semantic graph rather than the checker's
process-local type identities. Reflection reads declared meaning, not FFI
layout; `nupp.sizeof`, `nupp.alignof`, and `nupp.offsetof` use the build's
`layoutTarget`. Annotation names, arguments, values and referenced types
participate in the fingerprint, so changing serialization metadata invalidates a
cached comptime result even when the field types themselves are unchanged.

`nupp.fieldcodec.compile(nupp.reflect(R))` is the first non-PEG materializer.
For a record `R`, it produces a `nupp.fieldcodec.KeyedCodec<R>` whose `encode`
method copies exactly the record's present declared fields with `rawget`. Its
stable compatibility fingerprint is `t:` followed by those field names in
declaration order. The declared codec type must name the same nominal record.

Reflection of a runtime value, an unresolved type, or a non-record codec input
is **NUPP2418**. The ordinary materialization boundary, envelope, and size
diagnostics remain **NUPP2414** through **NUPP2416**.

```nupp
local m = {}

local record Position
    x: number
    y: number
end

const PositionCodec: nupp.fieldcodec.KeyedCodec<Position> = comptime do
    return nupp.fieldcodec.compile(nupp.reflect(Position))
end

function m.encode(position: Position): {[string]: any}
    return PositionCodec:encode(position)
end

return m
```

Reports: `NUPP2414`, `NUPP2415`, `NUPP2416`, `NUPP2418`. `nupp explain <code>`
says more.

### Built-in lints

```
 Lint                            Code      Category     Default
 ──────────────────────────────  ────────  ───────────  ───────
 missing-require                 NUPP2120  correctness  error
 exhaustiveness                  NUPP2107  correctness  warning
 string-pointer                  NUPP2501  suspicious   warning
 jit-callback                    NUPP2502  suspicious   warning
 lossy-narrowing                 NUPP2503  suspicious   warning
 customary-operator              NUPP2504  style        warning
 loop-invariant-closure          NUPP2505  suspicious   warning
 undocumented-raise              NUPP2506  suspicious   warning
 unused-binding                  NUPP2507  suspicious   warning
 discarded-result                NUPP2508  suspicious   warning
 reifiable-record                NUPP2509  performance  off
 gradual-projection              NUPP2511  suspicious   warning
 else-if                         NUPP2510  style        warning
 positional-record-construction  NUPP2512  style        warning
```

### Diagnostic codes with a worked example

- **NUPP0001**: A source file could not be read.
- **NUPP1002**: A required token is missing.
- **NUPP1006**: The typed layer appears in a plain Lua file.
- **NUPP2001**: A value does not fit the type it is bound to.
- **NUPP2004**: The field does not exist on that type.
- **NUPP2006**: A call's arguments are not arranged in a way it can be given.
- **NUPP2009**: A property view does not grant the requested access.
- **NUPP2010**: A complete value pack does not fit the required sequence.
- **NUPP2106**: An exported declaration needs a type annotation.
- **NUPP2107**: A dispatch leaves members of a closed set unhandled.
- **NUPP2119**: A declaration does not say where it lives.
- **NUPP2121**: A type pack is used where only one value type can appear.
- **NUPP2122**: A refinement cannot be enforced.
- **NUPP2123**: A metatable value does not fit the key it is written under.
- **NUPP2124**: An intersection is provably uninhabited.
- **NUPP2125**: No overload accepts a call.
- **NUPP2126**: Several overloads accept a call.
- **NUPP2127**: A declaration does not answer an associated type it is owed.
- **NUPP2128**: An associated type member cannot mean anything where it is
  written.
- **NUPP2129**: An associated type collides with another type member.
- **NUPP2133**: A recursive type alias is unsafe or exceeds its budget.
- **NUPP2134**: A projection names something that cannot be projected.
- **NUPP2135**: An associated type answers through itself.
- **NUPP2202**: A declaration is built with 'new'.
- **NUPP2206**: Only a record or a struct can be constructed.
- **NUPP2207**: A binding is read before it holds a value.
- **NUPP2208**: A constructor does not hold up its declaration.
- **NUPP2507**: A local is declared and nothing reads it.
- **NUPP2508**: A call that does nothing but return had its result dropped.
- **NUPP2511**: An associated type was erased because inference did not reach
  its head.
- **NUPP2512**: A record is built by field order rather than by naming its
  fields.
- **NUPP2605**: Adjusting a value pack would discard an affine value.
- **NUPP2701**: A non-suspending region can reach suspension.
- **NUPP2801**: A derive provider name is unknown or duplicated.
- **NUPP2802**: A generated derive member conflicts with the declaration.
- **NUPP2803**: A field cannot participate in derived Debug.
- **NUPP2804**: A record field has no valid derived default.
- **NUPP2805**: A record is not an unambiguous From conversion.
- **NUPP2806**: A record does not describe a supported JSON schema.
- **NUPP2807**: A derive dependency cycle has no valid lowering.
- **NUPP2808**: A derive exceeds a compiler generation limit.
- **NUPP3001**: `is` has nothing to test against this type.

## CLI

### CLI commands

`nupp help <command>` is the authoritative argument reference for one command;
`nupp help` lists every command. Use it when a focused skill names a command but
does not need every flag in context.

- `check`, `build`, `run`, and `fmt` work with source and generated Lua.
- `test` runs the configured test command; `coverage` runs it against a separate
  instrumented build and writes a report.
- `lsp` answers semantic source questions; `explain` expands a diagnostic; and
  `reference` returns these focused language and CLI skills.
- `tasks`, `clean`, `doc`, and `import-c` work with project configuration,
  outputs, documentation, and C declarations.

Data-producing commands accept `--json`, and then `--schema` describes their
JSON contract. Use the schema before automating against a command rather than
inferring fields from an example. The CLI uses 1-based byte lines and columns.

### Working with the toolchain

Positions are 1-based byte line and column numbers everywhere, matching the
compiler's own diagnostics. Colour is off whenever output is not a terminal, so
piped output never carries escapes.

- `nupp check --strict [FILE...]` type-checks. `--json` returns structured
  diagnostics with `help`, `related`, `notes` and machine-applicable `fixes`.
  Read `help` and `related` before editing, and apply a whole titled fix rather
  than picking single edits out of one: a fix is all-or-nothing.
- `nupp build --json [FILE...]` returns those diagnostics alongside what the
  build wrote, so one call says both what failed and what landed.
- `nupp explain CODE [--json]` gives the rule behind a code, a program that
  reports it, and the same program corrected. Every diagnostic carries a `docs`
  anchor pointing at the same reference.
- `nupp lsp inspect|definition|references|symbols|rename|actions --json` answer
  semantic questions without an editor. `inspect` on a call returns the callee's
  docblock, which is where `@raises` is read at a call site.
- `nupp fmt`, `nupp doc`, `nupp test`, `nupp fixpoint` format, document, test,
  and verify the compiler rebuilds byte-identically.

Every command taking `--json` also takes `--schema`, which prints the JSON
Schema of that output, so a consumer can be written against a contract rather
than against a sample.

The loop that works: run `check --json --strict`, apply a complete fix whose
title matches the intended repair, re-run, and run `nupp test` before
committing.

### Improving test coverage

Run `nupp coverage` to build a separate instrumented artifact, run the
configured tests, and write `build/reports/coverage/index.html`. It never
changes an ordinary build or its cache. Pass a suite name or other test
arguments to focus a run.

An agent can inspect an existing report without rerunning tests:

```bash
nupp coverage --report-json
```

That JSON names each file and its missed lines, functions, and branch arms.
Start with an uncovered branch or function that represents an observable
behaviour, read the indicated source, and add a test that establishes that
behaviour. Re-run the focused coverage command, then `nupp test` before
committing. Do not add tests solely to raise a percentage: prefer decisions,
error paths, and boundary cases whose expected result a test can state clearly.
The HTML report shows the same locations alongside highlighted Nupp and
generated Lua when visual context helps.
