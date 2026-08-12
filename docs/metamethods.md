# Metamethod contracts

Nupp types LuaJIT metamethod dispatch without taking ownership of runtime
metatable construction. A metamethod declaration is a trusted static contract:
it tells the checker how an operation behaves, while ordinary Lua code remains
responsible for installing the function with `setmetatable`, a registration
function, or a foreign runtime.

This division supports APIs such as tecs, where component and event records
declare their callable surface before a generic registrar installs `__call` on
the record's runtime type table.

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

`self` is a type binder scoped to the declaration. In the example, the
inherited `__call` contract is rebound from `Component` to `Position`, so a
call to `Position(...)` has type `Position`.

The declaration does not emit `Position.__call`, create another metatable, or
choose what the call constructs. If no runtime code installs `__call`, the
program can still fail at runtime. This is the same trust boundary as a
declaration file or an FFI signature.

## Runtime fulfillment

Runtime setup is ordinary Lua. A tecs-shaped event registrar can attach a
callable metatable after the record has been declared:

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

local function newEvent<E is Event>(event: metatable<E>)
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

The parameter is `metatable<E>`, not `E`. What `newEvent(OnSpawn)` passes is the
record's own runtime table, which is not an instance of the record. The body
calls `setmetatable` on it, which is the giveaway. Writing `event: E` claims to
take an instance and would be a different function.

Records retain their existing runtime namespace table. `new R(...)` stamps that
table as the instance metatable, and the table carries `__index = R` for
ordinary method lookup. A metamethod contract does not add a field to that
namespace and does not change this lowering.

Because that table *is* the metatable, writing a declared metamethod on it is
how a contract is fulfilled without `setmetatable` at all, and the value is held
to the contract there too:

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

```
 Key                             Held to
 ──────────────────────────────  ────────────────────────────────────────────
 one T contracts for             the declared contract, self specialized to T
 __mode                          a string
 __index, __newindex             a table to defer to, or a function to run
 any other key LuaJIT knows      a function, since LuaJIT calls it
 a __ name LuaJIT does not know  reported as a misspelling, with the repair
```

A table written directly under `__index` is what instances read their members
through, so an entry naming a declared member is held to what the declaration
says it is. A name the declaration does not have is an ordinary helper, and a
member the table leaves out may still be assigned afterwards; neither is
reported.

All of this is **NUPP2123** except the misspelling, which stays **NUPP2118**.

Only literals are checked. Nothing here can see what a function returns, so
`setmetatable(t, buildIt())` stays gradual.

## Supported contracts

The checker dispatches these contracts:

```
 Contract             Checked operation       Declared parameters
 ───────────────────  ──────────────────────  ───────────────────────────────
 __call               value(...)              receiver, then source arguments
 __index              value[key], value.name  receiver, key
 __newindex           value[key] = newValue   receiver, key, value
 __add, __sub, __mul  +, -, *                 left, right
 __div, __mod, __pow  /, %, ^                 left, right
 __unm                unary -                 operand
 __concat             ..                      left, right
 __len                #                       operand
 __lt, __le           ordered comparison      left, right
```

`__eq` and `__tostring` may also be declared as protocol surface. Equality is
always a valid Lua operation and always returns `boolean`, so the checker does
not need a contract to type the expression. Lua additionally requires both
operands to share the same `__eq` handler identity, which a function type
cannot express. `__tostring` participates in interface conformance but does
not change the static result of `tostring`, which is always `string`.

If the left operand has no binary contract, the checker consults the right
operand, matching Lua's fallback direction. The declared parameters still
describe the actual left and right values. A right-hand-only contract should
therefore type both positions rather than treating its receiver as the first
parameter automatically.

Primitive operators are checked when no contract applies. For example,
`#true`, arithmetic on unrelated values, and ordered comparison between plain
records are errors rather than being accepted unconditionally.

## Generic indexing

Metamethod function types can have their own type parameters. This allows a
typed key to determine the result of an indexed store:

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
metamethods are read from its bound and `self` is specialized back to the type
parameter.

## Contract inheritance and bounds

`is` declares trusted nominal contract inclusion:

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

The `is` clause is a claim, not a proof that runtime initialization has
already populated every field or installed every metamethod. Only interfaces
may be named as parents. Types that do not declare an `is` edge may still
satisfy an interface structurally, including its metamethod contracts.

Multiple parents are allowed:

```nupp
local record Task is Named, Callable
end
```

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

Inline methods are not metamethod definitions, even if their names begin with
`__`. Use `metamethod` for the static operation contract and install its
runtime implementation explicitly.

## `metatable<T>`

`metatable<T>` is a compiler-known type that erases to an ordinary Lua table. It
connects the standard metatable functions to their receiver:

```nupp
local record Task
end
local task: Task
local mt: metatable<Task> = {__index = {}}

setmetatable(task, mt)
local current: metatable<Task>? = getmetatable(task)
```

It is also the type a record's own name holds. `new Task(...)` stamps that table
on the instances it builds, so the table *is* their metatable and says so:

```nupp
local record Task
end

local mt: metatable<Task> = Task
local instance: table = {}

setmetatable(instance, Task)
```

That is what separates the declaration's table from an instance of it. `Task`
may stand wherever a `metatable<Task>` is wanted and nowhere an instance is; a
value built by `new Task(...)` is the reverse. Reaching a member through the
table reaches the record's, so `Task.make(...)`, `Task.field = ...` and the
metamethods installed on it all resolve.

Direct metatable literals reject unknown double-underscore keys, catching
mistakes such as `__cal`. Computed tables remain gradual. `as` retains its usual
assertion semantics and may override the checker.

## Deliberate exclusions

LuaJIT 3.0 gives the bit operators metamethods; the 2.1 backport that Nupp
generates for did not take them, and neither does the `bit` library those
operators are shorthand for. Contracts such as `__band`, `__bor`, `__bxor`,
`__bnot`, `__shl`, `__shr` and `__sar` are therefore rejected, and will
be reconsidered when the runtime dispatches them. `__idiv` is also rejected:
2.1 has no `//` at all, so it lowers to a floored division that dispatches
nothing.

For the same reason, `a += b` where `a` holds a value with an `__add` contract
calls `__add(a, b)` and not the `__add(a, b, true)` LuaJIT 3.0 specifies. The
in-place third argument is another part of the backport that did not come
across. Nothing depends on it; a metamethod that ignores its third argument
behaves identically under both.

`__gc` and `__close` are not static operation contracts. Deterministic cleanup
uses affine ownership and automatic lexical cleanup instead. `__pairs` is not
used to type `pairs`; LuaJIT's ordinary `pairs` accepts nominal record tables
directly.

Declaration-only struct metamethods are rejected. LuaJIT FFI metatypes must be
installed when `ffi.metatype` is called, so an erased promise would leave no
later runtime fulfillment point. Ordinary inline struct methods are supported
through the generated `ffi.metatype` method namespace.

Macro-generated protocol declarations are an `import-tl` concern. Comptime is
deliberately data-only and does not generate declarations, so a translated
macroexp-defined `__len`, such as tecs's `DoubleArray` contract, must be ejected
as an explicit declaration or a visible translation residue.

## Diagnostics

The principal diagnostics are:

- `NUPP2003`: no applicable primitive operation or metamethod contract.
- `NUPP2005`: a value has no callable type or `__call` contract.
- `NUPP2006` / `NUPP2007`: contract argument or arity mismatch.
- `NUPP2116`: a generic argument violates its `is` bound.
- `NUPP2117`: an invalid contract parent after `is`.
- `NUPP2118`: an invalid, duplicate, misspelled, or unsupported metamethod or
  inline method declaration.
