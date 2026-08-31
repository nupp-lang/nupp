---
order: 70
title: Metamethods
---

# Metamethod contracts

A `metamethod` declaration is a static contract: it tells the checker how an
operation behaves on a type, while ordinary Lua code installs the function that
performs it. Reach for one when a record's callable, indexable, or comparable
surface is put in place by `setmetatable`, a registrar, or a foreign runtime.

```nupp
local record Counter
    total: integer
    metamethod __len: function(self): integer
end
```

## Declaring a contract

Declare a metamethod inside a record or interface with `metamethod`, its Lua
name, and a function type:

```nupp:playground
local interface Component
    componentName: string
    metamethod __call: function(self, ...: any): self
end

local record Position is Component
    x: number
    y: number
end
```

`self` is a type binder scoped to the declaration. Here the inherited `__call`
contract is rebound from `Component` to `Position`, so a call to
`Position(...)` has type `Position`.

The declaration emits nothing. It does not write `Position.__call`, create a
metatable, or choose what the call constructs, so a program whose runtime never
installs `__call` fails at the first call. This is the same trust boundary as a
declaration file or an FFI signature.

::: deepdive
Nupp types LuaJIT metamethod dispatch without taking ownership of runtime
metatable construction, because the construction is where the variety is: a
registrar, a foreign runtime, and a hand-written `setmetatable` all end at the
same table, and a language feature that covered one of them would refuse the
other two.

What the contract does buy is enforcement in the other direction. A declared
contract is checked against the value that fulfills it, because a contract
nothing enforces is the same defect as one never written down: it is rendered,
documented, and never read. Computed metatables stay gradual, since tracking a
table's shape through arbitrary construction is a different problem.
:::

## Installing at runtime

Runtime setup is ordinary Lua, and there are two places to write it: a
registrar that calls `setmetatable`, or the record's own table.

### Registrars install the metatable

An event registrar can attach a callable metatable after the record has been
declared:

```nupp
local interface Event
    eventId: integer
    init: function(instance: self, ...: any)
    metamethod __call: function(self, ...: any): self
end

local record OnSpawn is Event
    entity: integer
end

OnSpawn.init = function(instance: OnSpawn, entity: integer)
    instance.entity = entity
end

local function newEvent<E is Event>(event: Type<E>)
    local id = 1
    local instanceMt = {__index = event}

    setmetatable(event, {__call = function(_self: E, ...: any): E
        local instance = setmetatable({eventId = id}, instanceMt) as E
        event.init(instance, ...)
        return instance
    end,})
end

newEvent(OnSpawn)
local spawned: OnSpawn = OnSpawn(42)
```

The contract sits on `Event` rather than on `OnSpawn`, so `newEvent` checks its
own body: the metatable it builds is a `metatable<E>`, and `E`'s bound says what
`__call` has to be. Putting the contract on the concrete record instead leaves
the registrar unchecked and only its call sites held to anything.

The parameter is `Type<E>`, not `E`. What `newEvent(OnSpawn)` passes is the
record's own visible type witness, which is not an instance of the record. The
body calls `setmetatable` on its runtime table. Writing `event: E` claims to
take an instance and would be a different function.

### Writing a metamethod on the record table

Records retain their existing runtime namespace table. `new R(...)` stamps that
table as the instance metatable, and the table carries `__index = R` for
ordinary method lookup. Because that table *is* the metatable its instances
carry, writing a declared metamethod on it fulfills the contract without
`setmetatable` at all, and the value is held to the contract there too:

```nupp
local record I64
    v: integer
    metamethod __tostring: function(self): string
end

I64.__tostring = function(self: I64): string
    return "I64(" .. tostring(self.v) .. ")"
end
```

## Checking a metatable literal

Wherever a table literal meets a `metatable<T>`, whether as an argument to
`setmetatable` or to any function declaring one, or as a binding or assignment
under a `metatable<T>` annotation, each of its `__` keys is checked:

| Key | Held to |
| --- | --- |
| one T contracts for | the declared contract, self specialized to T |
| `__mode` | a string |
| `__index`, `__newindex` | a table to defer to, or a function to run |
| any other key LuaJIT knows | a function, since LuaJIT calls it |
| a `__` name LuaJIT does not know | reported as a misspelling, with the repair |

A table written directly under `__index` is what instances read their members
through, so an entry naming a declared member is held to what the declaration
says it is. A name the declaration does not have is an ordinary helper, and a
member the table leaves out may still be assigned afterwards; neither is
reported.

All of this is reported against the declaration, and the misspelling is reported
against the name.

Only literals are checked. Nothing here can see what a function returns, so
`setmetatable(t, buildIt())` stays gradual.

## Supported contracts

The checker dispatches these contracts:

| Contract | Checked operation | Declared parameters |
| --- | --- | --- |
| `__call` | value(...) | receiver, then source arguments |
| `__index` | value[key], value.name | receiver, key |
| `__newindex` | value[key] = newValue | receiver, key, value |
| `__add`, `__sub`, `__mul` | +, -, * | left, right |
| `__div`, `__mod`, `__pow` | /, %, ^ | left, right |
| `__unm` | unary - | operand |
| `__concat` | .. | left, right |
| `__len` | # | operand |
| `__lt`, `__le` | ordered comparison | left, right |

`__eq` and `__tostring` may also be declared as protocol surface. Equality is
always a valid Lua operation and always returns `boolean`, so the checker does
not need a contract to type the expression. Lua additionally requires both
operands to share the same `__eq` handler identity, which a function type
cannot express. `__tostring` participates in interface conformance but does not
change the static result of `tostring`, which is always `string`.

Primitive operators are checked when no contract applies, so `#true`,
arithmetic on unrelated values, and ordered comparison between plain records
are errors rather than being accepted unconditionally.

### Fallback to the right operand

If the left operand has no binary contract, the checker consults the right
operand, matching Lua's fallback direction. The declared parameters still
describe the actual left and right values, so a right-hand-only contract types
both positions rather than treating its receiver as the first parameter
automatically.

```nupp
local record Scale
    factor: number
    metamethod __mul: function(left: number, right: Scale): number
end

local function apply(s: Scale): number
    return 2 * s
end
```

## Generic indexing

Metamethod function types can have their own type parameters, so a typed key
can determine the result of an indexed read or store:

```nupp
local record Key<T>
end

local record Store
    metamethod __index: function<T>(self, key: Key<T>): T
    metamethod __newindex: function<T>(self, key: Key<T>, value: T)
end

local store: Store
local nameKey: Key<string>

local name: string = store[nameKey]
store[nameKey] = "saved"
```

The checker infers `T` from `Key<T>` for both reads and writes. A bounded
receiver behaves the same way inside a generic function: fields, methods, and
metamethods are read from its bound, and `self` is specialized back to the type
parameter.

## Contract inheritance and bounds

`is` declares trusted nominal contract inclusion, and a type may name several
parents:

```nupp
local interface Named
    name: string
end

local interface Callable
    metamethod __call: function(self): self
end

local record Task is Named, Callable
end

local function start<T is Callable>(task: T): T
    return task()
end
```

The declaring type receives the inherited fields and metamethods, with the
parent's `self` rebound to the child. A bounded generic may use that inherited
surface, and call sites must satisfy the bound.

The `is` clause is a claim, not a proof that runtime initialization has already
populated every field or installed every metamethod. Only interfaces may be
named as parents. Types that do not declare an `is` edge may still satisfy an
interface structurally, including its metamethod contracts. See
[interfaces.md](types/interfaces.md#is-is-a-claim-not-a-proof) for
what the claim covers.

## Ordinary inline methods

An ordinary method body may be written directly in a record or struct. It uses
`function`, declares `self` as its first parameter, and is emitted on the
ordinary method namespace:

```nupp
local record Counter
    value: number

    function increment(self, by: number): self
        self.value = self.value + by
        return self
    end
end

local counter = new Counter(value = 0)
counter:increment(2)
```

No `:=` form is needed: `:` remains the separator between a declared field and
its type, while `function name(...) ... end` unambiguously introduces a body.
Inline signatures are hoisted before bodies are checked, so inline methods may
call one another regardless of declaration order.

Function-typed fields remain declaration-only and continue to support late
assignment:

```nupp
local record Task
    run: function(self: Task)
end

Task.run = function(self: Task)
    print(self)
end
```

An inline method is not a metamethod definition, even when its name begins with
`__`. Use `metamethod` for the static operation contract, and install its
runtime implementation explicitly.

## `metatable<T>`

`metatable<T>` is a compiler-known type that erases to an ordinary Lua table.
It connects the standard metatable functions to their receiver:

```nupp
local record Task
end
local task: Task
local mt: metatable<Task> = {__index = {}}

setmetatable(task, mt)
local current: metatable<Task>? = getmetatable(task)
```

It is not the type a record name holds: a record name is `Type<Task>`. A record
does use that runtime table as the metatable of its instances, but crossing
into the explicit Lua metatable API takes an explicit assertion:

```nupp
local record Task
end

local witness: Type<Task> = Task
local instance: table = {}

setmetatable(instance, witness as metatable<Task>)
```

`Task` may stand where `Type<Task>` is wanted and nowhere an instance is; a
value built by `new Task(...)` is the reverse. Reaching a member through the
witness reaches the record's, so `Task.make(...)`, `Task.field = ...` and the
metamethods installed on it all resolve.

::: deepdive
One runtime table wears two hats. It is the record's namespace, holding static
functions and the `__index` instances read through, and it is the metatable
those instances carry. Giving it one type would make `Task` interchangeable
with a metatable value everywhere, and the mistakes that follow are silent
ones: a table passed to `setmetatable` that was meant as a namespace still
runs, and misbehaves later.

So the witness type is `Type<Task>` and the assertion `witness as
metatable<Task>` is where a program says it means the other hat. `as` keeps its
usual semantics and may override the checker, which is the point: the crossing
is legal, and it is written down.
:::

## Excluded contracts

Several metamethods have no contract. Most are the ones the runtime Nupp
generates for does not dispatch; the rest are jobs another part of the language
already does.

### Bit operators

LuaJIT 3.0 gives the bit operators metamethods. The 2.1 backport Nupp generates
for did not take them, and neither does the `bit` library those operators are
shorthand for, so `__band`, `__bor`, `__bxor`, `__bnot`, `__shl`, `__shr` and
`__sar` are rejected. They will be reconsidered when the runtime dispatches
them.

```nupp
local record Flags
    bits: integer
    metamethod __band: function(self, other: Flags): Flags
end
```

```text [nupp check flags.nupp]
error: NUPP2118: metamethod __band is not dispatched by this LuaJIT target
```

`__idiv` is rejected for the same reason: 2.1 has no `//` at all, so it
[lowers to a floored division](syntax.md#lowered-syntax) that dispatches
nothing.

### In-place arithmetic

`a += b` where `a` holds a value with an `__add` contract calls `__add(a, b)`,
not the `__add(a, b, true)` LuaJIT 3.0 specifies. The in-place third argument
is another part of the backport that did not come across. Nothing depends on
it: a metamethod that ignores its third argument behaves identically under
both.

### Cleanup and iteration

`__gc` and `__close` are not static operation contracts. Deterministic cleanup
uses [affine ownership](../runtime/ownership/index.md) and automatic lexical cleanup instead.
`__pairs` is not used to type `pairs`, because LuaJIT's ordinary `pairs`
accepts nominal record tables directly.

### Struct metamethods

Declaration-only struct metamethods are rejected. LuaJIT FFI metatypes must be
installed when `ffi.metatype` is called, so an erased promise would leave no
later runtime fulfillment point. Ordinary inline struct methods are supported
through the generated `ffi.metatype` method namespace.

### Macro-generated declarations

Macro-generated protocol declarations are an `import-tl` concern. Comptime is
deliberately data-only and does not generate declarations, so a translated
macroexp-defined `__len` contract must be ejected as an explicit declaration or
a visible translation residue.

::: seealso
- [interfaces.md](types/interfaces.md#metamethod-contracts) for how a
  contract participates in interface satisfaction
- [generics.md](types/generics.md#generic-metamethods) for the
  inference rules behind a generic contract
- [records.md](types/records-and-structs.md#names-hold-their-table) for the
  namespace table a contract is installed on
:::

## FAQ

### Does a metamethod contract emit any code?

No. The declaration is checked and erased, so the generated Lua for a record
with contracts is the generated Lua for the same record without them. The
runtime behavior comes entirely from whatever installs the function.

### Must a record declare `is` to satisfy a contract?

No. A type that declares no `is` edge may still satisfy an interface
structurally, metamethod contracts included. `is` adds the parent's fields and
metamethods to the declaring type, which structural satisfaction does not.

### Why does a declared `__eq` not change how equality is checked?

Equality is always a valid Lua operation returning `boolean`, so nothing about
the expression's type depends on a contract. Lua also requires both operands to
share one `__eq` handler identity, which a function type cannot express, so
`__eq` is declarable as protocol surface and no more.
