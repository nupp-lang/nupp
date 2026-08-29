---
order: 230
---

# Records and structs

A `record` is a Lua table with a nominal name, and a `struct` is FFI cdata with
a fixed C layout. Choosing between them is choosing a representation.

```nupp
local record Point
    x: number
    y: number
end

local struct Pixel
    x: float
    y: float
end
```

## Records

A record declaration builds one runtime table, uses it as the metatable of
every instance, and gives the name a nominal type:

```nupp:playground
local record Point
    x: number
    y: number

    function length(self): number
        return math.sqrt(self.x * self.x + self.y * self.y)
    end
end

local p = new Point(x = 3, y = 4)
print(p:length())
```

```lua [Generated Lua]
const Point = {} Point.__index = Point
local p = setmetatable({ x = 3, y = 4 }, Point)
```

Construction is by name. A record has no positional form, because field order in
a table is not meaningful.

The declaration's runtime table is the type's identity, which is what lets
`p is Point` lower to a `getmetatable` comparison. An instance is a value that
came from the declaration, not only one the declaration stamped itself: a
constructor may link back rather than stamping, giving instances their own
metatable whose `__index` is the record, which is how a prototype-style
registrar builds them. The test reaches the record through `__index` so both
arrive at the same answer, which works because a record is its own prototype.
A value with no metatable, another record's instance, and the declaration's own
table all answer `false`.

### Names hold their table

`Point` is a type and also a value: the runtime table above. Its value is the
declaration's visible `Type<Point>` witness.

```nupp
local witness: Type<Point> = Point
local p: Point = new Point(x = 3, y = 4)
```

Neither stands where the other is wanted. `Point` may be written to when a
[metamethod contract](../concepts/metamethods.md#declaring-a-contract) is
installed; `p` may not. `p` may be read for its fields and passed where a
`Point` is wanted; `Point` may not. A record name is not implicitly a
`metatable<Point>`: that type remains for an explicit table passed to Lua's
metatable functions. `Point is Point` is answered without running, because a
declaration's own table is never one of the values it stamps.

Reaching a member through the table reaches the record's, so `Point.length`,
`Point.make(...)` and a nested `Point.Inner` all resolve as they always did. A
function that takes a declaration's table rather than an instance says so:

```nupp
local function register<P is Shape>(shape: Type<P>)
```

### Constructors and result policies

A constructor creates `self` before its body runs, fills that instance, and
returns it after the body succeeds:

```nupp
local record File
    path: string

    constructor(self, path: string): affine(File, File.destroy)
        self.path = path
    end

    function read(self): string
        return self.path
    end

    function destroy(takes self): nil
        os.remove(self.path)
    end
end

local file = new File("scratch.txt")
print(file:read())
```

With no result annotation, `new File(...)` has the ordinary `File` type. An
explicit result states a policy introduced by successful construction. It must
be one value that erases to `File`; `affine(File, File.destroy)` is valid
because it changes the obligation, not the runtime representation. A different
record, a borrowed view, a pinned view, or a result pack is rejected.

The cleanup may be an instance method on the same record. Inline signatures are
hoisted before constructor results resolve, so `File.destroy` is the ordinary
function identity stored on the record table. The affine view remains a `File`
at run time and exposes `File`'s methods directly, with no wrapper record or
shared interface.

Constructor overload selection includes the complete result policy. Overloads
still differ by parameter pack, never by result alone; after argument selection,
the winning overload determines whether the value is ordinary, affine with a
cleanup, or transfer-only. See [affine
types](affine-types.md#constructors-can-introduce-the-policy) for the complete
result rule.

### Field defaults

A stored record or struct field may declare a constant construction default:

```nupp
local record Settings
    host: string = "localhost"
    port: integer = 8080
    tags: {string} = {}
end

local settings = new Settings(port = 9000)
```

Omitted fields use their declarations; written arguments still win. Defaults are
explicit, and types do not acquire universal zero values. A default is a closed
scalar or table literal that fits the field type, so it is stable across module
and comptime boundaries. Each construction evaluates it freshly, so a mutable
table default is never shared.

A constructor begins with the same defaults already installed, then its body
runs. The body can read, refine, or replace them, and a defaulted required field
does not need another assignment merely to satisfy constructor completeness.
Interfaces describe contracts rather than stored values and therefore cannot
declare field defaults.

### Private fields

`private` keeps a record field inside the canonical module that declares the
record:

```nupp
record model.Box<T>
    private value: T

    function get(self: model.Box<T>): T
        return self.value
    end
end
```

The declaring module may construct, read, and write it; another checked module
sees the nominal type and its public operations but cannot access or initialize
the field. Privacy applies through generic instantiation and module summaries.
It is a checked-language abstraction boundary, not a runtime sandbox against
generated Lua or explicit gradual interop.

Records alone support private fields, and the checker says so anywhere else.
Structs expose C layout and interfaces declare public contracts, so both reject
the modifier.

### Inline methods and static functions

An inline function whose first parameter is named `self` is an instance method,
emitted on the ordinary method namespace. Without that parameter it is a static
function, called through the declaration table with `.`. Inline signatures are
hoisted before any body is checked, so methods may call each other in any order.

```nupp
local record Counter
    value: number

    function increment(self, by: number): self
        self.value = self.value + by
        return self
    end
end
```

`self` is a type binder scoped to the declaration, so a method returning `self`
returns the concrete receiver type rather than the declaring type.

A function-typed *field* is a declaration without a body, which supports late
assignment:

```nupp
local record Task
    run: function(self: Task)
end

Task.run = function(self: Task)
    print(self)
end
```

Inline methods are not metamethod definitions, even when their names begin with
`__`. See [metamethod contracts](interfaces.md#metamethod-contracts) for the
declaration that does install operator behavior.

### Recursive and nested declarations

Inside its own body a declaration answers to its simple name:

```nupp
local record Path
    points: {Point}
    cutFrom: Path?
end
```

Records may nest other declarations, which reach through the table their owner
sits on:

```nupp
local m = {}

record m.Shapes
    record Point
        x: number
    end

    type Id = uint32
end

local p: m.Shapes.Point = new m.Shapes.Point(x = 1)
```

## Structs

A struct declaration builds an FFI type and gives it a metatype, so the fields
are offsets into real memory rather than hash lookups:

```nupp
local struct Vec2
    x: float
    y: float
end
```

```lua [Generated Lua]
const __nuppMt_Vec2 = {__index = {}}
const Vec2 = ffi.metatype(ffi.typeof("struct { float x; float y; }"), __nuppMt_Vec2)
```

Real memory, real widths. A `float` field truncates the way a C `float` does.

Construction has three forms, and a struct binding is never nil, so the third is
complete on its own:

```nupp
local a = new Vec2(1.0, 2.0) -- named
local b = Vec2(1.0, 2.0) -- positional, in field order
local c: Vec2 -- zero-initialized
```

### Struct field types

The field type has to be reifiable, meaning something with a C layout:

- the numeric primitives: `number`, `float`, `boolean`, `integer`, and the
  sized integers `int8` through `uint64`;
- another struct, by value;
- any pointer `T*`, and the nullable `T*?`;
- a fixed C array `T[N]`.

Everything GC-managed is refused: `string`, `{T}`, function
types, and even `number?`, because an optional needs a representation the C
layout does not have. `cstring` and `voidptr` are allowed in a `cdef struct` but
not in a Nupp `struct`, since a GC-managed struct gives them no anchor.

#### Fixed arrays

`T[N]` sits inline, N elements in the struct's own bytes with no indirection,
which is how a C struct carries a vector:

```nupp
local struct Vertex
    pos: float[3]
    uv: float[2]
    id: int32
end

local v = new Vertex()
v.pos[0] = 1.5
v.pos[2] = 3.5
print(v.pos[0] + v.pos[2])
```

`Vertex` is 24 bytes: twelve for `pos`, eight for `uv`, four for `id`, and no
padding. The elements are zero-based, like every C array.

The element may itself be a struct, and it is stored by value:

```nupp
local struct Cell
    a: float
    b: float
end

local struct Grid
    cells: Cell[4]
    n: int32
end

local g = new Grid()
g.cells[0].a = 1
g.cells[3].b = 9
```

`T[?]` is **not** a field. A variable-length array has no size, so a struct
holding one would have none either, so it is refused. Use a pointer and hold
the count yourself, which is what C does.

#### Pointing at itself

A struct may hold a pointer to its own declaration, which is how a linked
structure is written:

```nupp
local struct Node
    next: Node*?
    value: int32
end

local head = new Node(nil, 1)
local tail = new Node(nil, 2)
head.next = tail
print(head.next.value)
```

By value it cannot, since `next: Node` would have to contain a copy of itself
and so has no size. That is refused, and the repair it names is the pointer.

### Value or reference

A struct is a value type in memory, and a nested struct field is stored by
value. A struct held in a Lua variable is a reference to that cdata, so passing
one to a function and mutating a field is visible to the caller:

```nupp
local function move(v: Vec2)
    v.x = v.x + 1
end

local origin = new Vec2(0.0, 0.0)
move(origin)
print(origin.x) -- 1
```

Copy explicitly when you want a copy.

## Choosing

Reach for a **record** when you want identity, dynamism, arbitrary field types,
metamethod contracts, or ordinary GC. That is most application code. Reach for a
**struct** when the layout matters: interop with C, a large array of small
values, or a hot field access you want to be an offset instead of a hash lookup.

|  | `record` | `struct` |
| --- | --- | --- |
| Runtime | Lua table plus metatable | FFI cdata |
| Field access | Hash lookup | Offset |
| Field types | Anything | C-representable only |
| Construction | `new R(x = 1)` | `new S(x = 1)` or `S(1, 2)` |
| Binding with no initializer | Rejected | Zero-initialized |
| Memory | Garbage collected | Managed by the FFI |
| Array field `{T}` | Allowed | Rejected |
| Property capabilities | `readonly` / `writeonly` | Ordinary fields only |
| Private fields | Allowed | Rejected |
| Nested declarations | Allowed | Rejected |
| Inline methods | Yes | Yes, through `ffi.metatype` |
| Metamethod contracts | Yes | Rejected |
| `is` test | Reaches the record through `__index` | `ffi.istype(S, v)` |

Both are nominal. Two records with identical fields are different types, and
neither is assignable to the other. A record is assignable to a structural shape
with the same fields, so width subtyping works in that direction only.

::: deepdive
Choosing between a record and a struct is a declaration rather than an
optimization the compiler makes, because the two have genuinely different
runtime meanings. A struct is FFI cdata with a fixed layout and no hash part; a
record is a table with a metatable, identity, and dynamism. A compiler that
picked for you would be choosing your memory representation from a type
annotation, and would be wrong the first time a value crossed a C boundary.
:::

`layoutof(T)` reports how a declaration is laid out, which is what lets a codec,
a snapshot writer, or a GPU vertex-attribute descriptor be derived from the
declaration rather than maintained beside it. See
[c-interop.md](../concepts/c-interop.md#read-a-structs-layout) for what it
returns.

## FAQ

### Are records classes or ordinary Lua tables?

A record declaration creates the table and metatable pattern ordinary Lua code
already uses. It adds a nominal type to checking but no class runtime or hidden
instance wrapper. See [records](#records) for the lowering, and [metamethod
contracts](../concepts/metamethods.md#declaring-a-contract) for the explicit
declaration an API needs when it wants operator behavior.

### Do methods require a shared interface?

An instance reaches its inline methods through the record table, so a concrete
record API does not need an interface merely to call `file:read()`. See
[satisfaction is structural](interfaces.md#satisfaction-is-structural) for when
an interface earns its place: several unrelated types satisfying one contract,
not plumbing between a record and an ownership view of that record.

### Does an affine constructor wrap the record instance?

No. An affine constructor result adds a checker obligation to the record it
already builds, so the value keeps the record's methods and runtime identity.
See [consumption and lexical
destruction](ownership.md#consumption-and-lexical-destruction) for where the
cleanup is discharged.

::: seealso
- [affine-types.md](affine-types.md#constructors-can-introduce-the-policy) for
  the result policies a constructor may state
- [properties.md](properties.md) for independent read and write views of a
  record field
- [c-interop.md](../concepts/c-interop.md#export-ordinary-structs-to-c) for
  passing a struct across the C boundary
- [structure-of-arrays.md](../concepts/structure-of-arrays.md) for storing many
  small records field-by-field instead
:::
