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

`self` is a type binder scoped to the declaration. Here the inherited `__call`
contract is rebound from `Component` to `Position`. Calling a `Position`
instance therefore returns another `Position`.

The metamethod contract emits no function. Install `Position.__call` before
calling an instance. Calling the declaration itself, `Position(...)`, uses its
generated or explicit constructor and does not consult the instance contract.

## Installing at runtime

Install an instance metamethod on the record's own table. The declaration's
construction handler is reserved; it cannot be replaced through `setmetatable`.

### Construction and instance calls

A constructor and an instance call can accept different arguments:

```nupp
local record Handler
    prefix: string

    constructor(self, prefix: string)
        self.prefix = prefix
    end

    metamethod __call: function(self, request: string): string
end

Handler.__call = function(self: Handler, request: string): string
    return self.prefix .. request
end

local make = Handler
local handler = make("Received: ")
assert(handler("hello") == "Received: hello")
```

For a record `R`, construction belongs to the metatable of the declaration;
`R.__call` belongs to its instances. The declaration metatable is protected at
runtime, including when Lua holds the declaration. Debug APIs that bypass Lua's
metatable protection are outside this contract.

### Factory registrars

A registrar that used to replace a declaration's `__call` can return a factory:

```nupp
local interface Event
    eventId: integer
    init: function(instance: self, ...: any)
end

local record OnSpawn is Event
    entity: integer
end

OnSpawn.init = function(instance: OnSpawn, entity: integer)
    instance.entity = entity
end

local function register<E is Event>(event: Type<E>): function(...: any): E
    local id = 1
    local instanceMt = {__index = event}
    return function(...: any): E
        local instance = setmetatable({eventId = id}, instanceMt) as E
        event.init(instance, ...)
        return instance
    end
end

local spawn = register(OnSpawn)
local spawned: OnSpawn = spawn(42)
```

The parameter `Type<E>` carries the declaration and its members. The factory
owns this custom allocation path. An interface's instance `__call` contract
does not provide a construction signature for `Type<E>`.

### Writing a metamethod on the record table

Records retain their existing runtime namespace table. `R(...)` stamps that
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
`setmetatable(t, buildIt())` stays unchecked.

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

```nupp:fragment
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

local counter = Counter(value = 0)
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

```nupp:fragment
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
value built by `Task(...)` is the reverse. Reaching a member through the
witness reaches the record's, so `Task.make(...)`, `Task.field = ...` and the
metamethods installed on it all resolve.

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

```nupp:refused
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
