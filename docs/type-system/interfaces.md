# Interfaces

An interface names a set of members. It has no runtime value at all — the
declaration emits nothing.

```nupp
local interface Named
    name: string
end
```

Members and indexers may be declared `readonly` and `writeonly` independently.
This controls both access and variance; see
[property capabilities](properties.md).

## Satisfaction is structural

A type satisfies an interface by carrying its members. No declaration is
required:

```nupp
local record Circle
    name: string
    radius: number
end

local n: Named = new Circle {name = "c", radius = 1}   -- fine
```

A plain table shape works too:

```nupp
local n: Named = {name = "anonymous"}
```

When comparing member functions, the receiver parameter is skipped on both
sides, since each implementation names it for itself.

## `is` is a claim, not a proof

```nupp
local record Tagged is Named
    name: string
    weight: number
end
```

`is` does two things. It inherits the parent's members and metamethods, with
`self` rebound from the parent to the child. And it declares satisfaction,
which the checker trusts rather than re-proving.

That second part matters: a record declaring `is Component` satisfies
`Component` even if a runtime registrar has not installed the members yet. It
is the same trust boundary as a declaration file or an FFI signature. If
nothing ever installs them, the program still fails at runtime.

Only interfaces may be named after `is`; anything else is NUPP2117. Multiple
parents are allowed:

```nupp
local record Task is Named, Callable end
```

## Bounded generics

An interface is the usual bound for a type parameter:

```nupp
local function start<T is Callable>(task: T): T
    return task()
end
```

Inside the body, fields, methods, and metamethods are read from the bound, and
`self` specializes back to the type parameter. Bounds are checked where a
generic is instantiated, not inside the subtyping relation.

## `is` at runtime

The `is` operator tests a value's type:

```nupp
if shape is Circle then
    print(shape.radius)
end
```

It compiles for `nil`, the primitives, function types, records (reaching the
declaration through `__index`, so a value the declaration built answers yes
whether it was stamped directly or linked back to), and structs
(`ffi.istype`).

A test the subject's own type already answers does not run at all. `c is Shape`
where `c` is a `Circle` and `Circle is Shape` is `true` by the declaration, and
an optional's nil is the only part left to ask — `maybe is Shape` compiles to
`maybe ~= nil`. This works whatever the interface can or cannot test at run
time, and is the usual reason `is` against an interface succeeds.

Because it trusts the type, an `is` in the tail of an exhaustive chain over a
union is answered by what the earlier branches ruled out rather than re-checked.
That is the same trust the checker already extends — it lets the branch read the
narrowed type's fields without a test — so a value that reached the union
through an `as` it did not deserve is answered by the cast, not by `is`.

Where the subject's type does not settle it, an interface has no runtime table
of its own. It can still be tested two ways:

**A tag it already declares.** An interface whose fields carry literal types has
said what its test is — the field admits that value and nothing else — so the
test is read off the declaration with nothing written:

```nupp
local interface Circle
    kind: "circle"
    radius: number
end
```

```lua
-- `x is Circle` becomes
(type(x) == "table" and x.kind == "circle")
```

That is what lets a decoded table answer `is`. It applies to interfaces only: a
record and a struct already answer exactly, so a derived test beside either
would be a second answer chosen by whether the fields happened to be literals.

**A `matches` block**, which wins over the tags when both are present.

With neither, and against an alias, there is nothing to test and that is
NUPP3001 at code generation.

Note that `x is integer` compiles to `type(x) == "number"`. Integrality is not
checked at runtime.

## Default implementations

An interface may implement what it declares, and a declaration that takes the
contract takes the behaviour with it:

```nupp
local interface Greeter
    name: string

    function greet(): string
        return "hello, " .. self.name
    end
end

local record Person is Greeter
    name: string
end
```

```lua
local Greeter = {}
function Greeter.greet(self)
return "hello, " .. self.name
end

local Person = {} Person.__index = Person Person.greet = Greeter.greet
```

The body is emitted **once** and referenced, not copied — resolved where the
implementor is written rather than looked up at run time, so there is no chain
and no indirection. A struct takes it through its metatype's index table, and a
chain of interfaces passes it along.

This is the one thing that gives an interface a runtime presence. An interface
that declares only signatures still emits nothing at all, so the table is paid
for by the feature rather than by every interface — and it is why an interface
carrying defaults has to be reachable from an implementor in another module.

**Replacing one has to be said.** `@override` is required on a member that
replaces an inherited default, and is equally an error on one that replaces
nothing. That catches the two failures Java cannot: the misspelling that
silently defines a new method instead of overriding, and the interface that
later adds a default which silently shadows an implementor's method.

**Two interfaces providing the same name is refused.** They are two
implementations and no reason to prefer either, so the declaration writes the
member itself to say which behaviour it means.

## Metamethod contracts

An interface or record may declare how an operator behaves on it:

```nupp
local interface Component
    componentName: string
    metamethod __call: function(self, ...: any): self
end

local record Position is Component
    x: number
    y: number
end
```

The declaration is a static contract. It emits no `__call` field, builds no
metatable, and decides nothing about what the call constructs — ordinary Lua
code installs the function with `setmetatable`, a registrar, or a foreign
runtime. Inheriting the contract rebinds `self`, so `Position(...)` has type
`Position`.

The declarable set:

```
 Contract                    Operation
 ──────────────────────────  ──────────────────────────
 __call                      value(...)
 __index                     value[key], value.name
 __newindex                  value[key] = v
 __add __sub __mul           + - *
 __div __mod __pow           / % ^
 __unm                       unary -
 __concat                    ..
 __len                       #
 __lt __le                   ordered comparison
 __eq __tostring             protocol surface only
```

`__eq` and `__tostring` participate in conformance but do not change a result
type: `==` is always `boolean` and `tostring` is always `string`.

When the left operand has no contract, the checker consults the right one,
matching Lua's fallback direction. The declared parameters still describe the
actual left and right values, so a right-hand-only contract has to type both
positions.

Structs cannot declare metamethod contracts, because LuaJIT metatypes must be
installed when `ffi.metatype` is called and an erased promise would leave no
later fulfillment point.

The bit-operator contracts (`__band`, `__bor`, `__bxor`, `__bnot`, `__shl`,
`__shr`, `__sar`) and `__idiv` are rejected: the LuaJIT 2.1 backport does not
dispatch them. `__gc` and `__close` are not contracts either — deterministic
cleanup is [ownership](../ownership.md) and `with`.

[The metamethod reference](../metamethods.md) covers generic indexing, runtime
fulfillment, `metatable<T>`, and the full set of exclusions.

## Diagnostics

- **NUPP2116** — a generic argument violates its bound.
- **NUPP2117** — `is` names something that is not an interface.
- **NUPP2118** — an invalid, duplicate, or unsupported metamethod contract, or
  an interface method given a body.
- **NUPP3001** — `is` used against a type with no runtime identity.
