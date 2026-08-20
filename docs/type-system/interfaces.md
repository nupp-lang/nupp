# Interfaces

An interface names a set of members that any type carrying them satisfies. The
declaration emits nothing at run time unless it supplies a default
implementation.

```nupp:playground
local interface Named
    name: string
end

local record Circle
    name: string
    radius: number
end

local n: Named = new Circle(name = "c", radius = 1)
```

## Satisfaction is structural

A type satisfies an interface by carrying its members. No declaration is
required, and a plain table shape works the same way:

```nupp
local n: Named = {name = "anonymous"}
```

Members and indexers may be declared `readonly` and `writeonly` independently,
which controls both access and variance. See [properties.md](properties.md) for
what each capability admits.

## Sealed interfaces

`sealed` closes structural satisfaction when an interface is a trust boundary:

```nupp
sealed interface span.Span<T>
    readonly count: integer
    get: function(self: Span<T>, index: integer): T
end
```

Only a record, struct, or child interface declared with `is span.Span<T>` in the
same module may satisfy that contract. A type in another module is rejected even
when it has the same fields, and it cannot add the `is` claim itself. The owning
module can therefore keep the representation private and export only
constructors returning the interface.

Sealing is entirely static. It emits no tag, wrapper, virtual dispatch, or
runtime test. It earns its place when the visible methods rely on facts that
mere field shape cannot prove, such as a pointer agreeing with a count. An `any`
value remains gradual and can cross the boundary with the usual loss of static
guarantees.

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
`self` rebound from the parent to the child. And it declares satisfaction, which
the checker trusts rather than re-proving.

That second part matters: a record declaring `is Component` satisfies
`Component` even if a runtime registrar has not installed the members yet. It is
the same trust boundary as a declaration file or an FFI signature. If nothing
ever installs them, the program still fails at run time.

Only interfaces may be named after `is`, and anything else reports `NUPP2117`.
Multiple parents are allowed:

```nupp
local record Task is Named, Callable
end
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
generic is instantiated, not inside the subtyping relation. See
[generics.md](generics.md#constraints-use-is) for inference and the rest of the
bound rules.

## `is` at runtime

The `is` operator tests a value's type:

```nupp
if shape is Circle then
    print(shape.radius)
end
```

It compiles for `nil`, the primitives, function types, records, and structs. A
record reaches its declaration through `__index`, so a value the declaration
built answers yes whether it was stamped directly or linked back to; a struct
uses `ffi.istype`. `x is integer` compiles to `type(x) == "number"`, because
integrality is not checked at run time.

### Tests that do not run

A test the subject's own type settles does not run at all:

```nupp
local maybe: Shape? = pick()
if maybe is Shape then -- compiles to `maybe ~= nil`
    use(maybe)
end
```

`c is Shape` where `c` is a `Circle` and `Circle is Shape` is `true` by the
declaration, and an optional's nil is the only part left to ask. This works
whatever the interface can or cannot test at run time, and it is the usual
reason `is` against an interface succeeds.

Because it trusts the type, an `is` in the tail of an exhaustive chain over a
union is answered by what the earlier branches ruled out rather than re-checked.
That is the same trust the checker already extends when it lets a branch read
the narrowed type's fields without a test, so a value that reached the union
through an `as` it did not deserve is answered by the cast, not by `is`.

### Tags an interface already declares

Where the subject's type does not settle it, an interface has no runtime table
of its own. An interface whose fields carry literal types has already said what
its test is, since the field admits that value and nothing else:

::: code-group
```nupp [Nupp]
local interface Circle
    kind: "circle"
    radius: number
end
```

```lua [Generated Lua]
-- `x is Circle` becomes
(type(x) == "table" and x.kind == "circle")
```
:::

That is what lets a decoded table answer `is`. It applies to interfaces only: a
record and a struct already answer exactly, so a derived test beside either
would be a second answer chosen by whether the fields happened to be literals.

### Refinement tests

A [`satisfies` declaration](refinements.md) states the test outright, and it
wins over the tags when both are present. With neither, and against an alias,
there is nothing to test, and code generation reports `NUPP3001`.

::: deepdive
An interface emits no runtime table, so `is` against one is answered by static
elision, by a tag its own literal-typed fields already declare, or by a
`satisfies` test it names. Registering conformance on every declaration was
designed and verified, then declined: elision and tags already answered every
case except an untagged interface against a subject whose type does not prove
it, which is one case weighed against a runtime table on every interface in the
language.
:::

## Default implementations

An interface may implement what it declares, and a declaration that takes the
contract takes the behavior with it:

::: code-group
```nupp [Nupp]
local interface Greeter
    name: string

    function greet(self): string
        return "hello, " .. self.name
    end
end

local record Person is Greeter
    name: string
end
```

```lua [Generated Lua]
const Greeter = {}
function Greeter.greet(self)
return "hello, " .. self.name
end

const Person = {} Person.__index = Person Person.greet = Greeter.greet
```
:::

The body is emitted **once** and referenced, not copied. It is resolved where
the implementor is written rather than looked up at run time, so there is no
chain and no indirection. A struct takes it through its metatype's index table,
and a chain of interfaces passes it along.

This is the one thing that gives an interface a runtime presence. An interface
declaring only signatures still emits nothing at all, so the table is paid for
by the feature rather than by every interface. It is also why an interface
carrying defaults has to be reachable from an implementor in another module.

Two interfaces providing the same name is refused. They are two implementations
and no reason to prefer either, so the declaration writes the member itself to
say which behavior it means.

### Replacing a default

`@override` is required on a member that replaces an inherited default, and is
equally an error on one that replaces nothing:

```nupp
local record Shouter is Greeter
    name: string

    @override
    function greet(self): string
        return "HELLO, " .. self.name
    end
end
```

That catches the two failures Java cannot: the misspelled name that silently
defines a new method instead of overriding, and the interface that later adds a
default which silently shadows an implementor's method.

For an overloaded default, replacement is matched by parameter pack rather than
source name alone. Each repeated method body is a separate entry, so a record
may `@override` one signature and continue inheriting the others, and no
`@overload` annotation is needed because repeated names form the overload set.
See [overloads.md](overloads.md#default-implementations-and-override) for
complete examples, including bodyless contracts and defaults contributed by
separate interfaces.

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
metatable, and decides nothing about what the call constructs. Ordinary Lua code
installs the function with `setmetatable`, a registrar, or a foreign runtime.
Inheriting the contract rebinds `self`, so `Position(...)` has type `Position`.

`__eq` and `__tostring` participate in conformance but do not change a result
type: `==` is always `boolean` and `tostring` is always `string`. When the left
operand has no contract, the checker consults the right one, matching Lua's
fallback direction, and the declared parameters still describe the actual left
and right values, so a right-hand-only contract has to type both positions. See
[metamethods.md](../concepts/metamethods.md#supported-contracts) for the
declarable set and the parameters each one takes.

Structs cannot declare metamethod contracts, because LuaJIT metatypes must be
installed when `ffi.metatype` is called and an erased promise would leave no
later fulfillment point. The bit-operator contracts (`__band`, `__bor`,
`__bxor`, `__bnot`, `__shl`, `__shr`, `__sar`) and `__idiv` are rejected because
the LuaJIT 2.1 backport does not dispatch them. `__gc` and `__close` are not
contracts either, since deterministic cleanup is
[ownership](ownership.md).

## FAQ

### When is an interface better than a record?

When several unrelated types must answer the same contract, or when a module
wants to publish a shape without publishing its representation. A concrete
record API needs no interface merely to call its own methods. See [records and
structs](records.md#choosing) for which representation a type wants.

### Why does `is` against an interface usually compile to nothing?

Because the subject's declared type has already answered it. An interface has no
runtime table, so the checker elides the test wherever the type proves it, and
falls back to a literal-field tag or a `satisfies` refinement where it does not.

### Can an interface add fields to the types that satisfy it?

No. An interface declares members and, optionally, default implementations for
its own methods, but satisfaction is a fact about the implementor's own members.
A default implementation is one shared function referenced from the implementor,
not a field copied into it.

::: seealso
- [refinements.md](refinements.md) for the `satisfies` test an interface may
  carry
- [properties.md](properties.md) for `readonly` and `writeonly` members
- [metamethods.md](../concepts/metamethods.md) for generic indexing, runtime
  fulfillment, `metatable<T>`, and the full set of exclusions
- [overloads.md](overloads.md#default-implementations-and-override) for
  `@override` against an overload set
:::
