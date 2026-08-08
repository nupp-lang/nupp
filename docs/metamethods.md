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
end

local record OnSpawn is Event
    entity: integer
    metamethod __call: function(self, entity: integer): self
end

OnSpawn.init = function(instance: OnSpawn, entity: integer)
    instance.entity = entity
end

local function newEvent<E is Event>(event: E)
    local id = 1
    local instanceMt = {__index = event}

    setmetatable(event, {
        __call = function(_self: E, ...: any): E
            local instance = setmetatable({eventId = id}, instanceMt) as E
            event.init(instance, ...)
            return instance
        end,
    })
end

newEvent(OnSpawn)
local spawned: OnSpawn = OnSpawn(42)
```

The body of `newEvent` remains gradual where it builds a metatable for generic
`E`. The bound still checks every call to `newEvent`, and the concrete
`OnSpawn` declaration checks calls made after registration.

Records retain their existing runtime namespace table. `new R{...}` stamps that
table as the instance metatable, and the table carries `__index = R` for
ordinary method lookup. A metamethod contract does not add a field to that
namespace and does not change this lowering.

## Supported contracts

The checker dispatches these contracts:

| Contract | Checked operation | Declared parameters |
| --- | --- | --- |
| `__call` | `value(...)` | receiver, then source arguments |
| `__index` | `value[key]`, `value.name` | receiver, key |
| `__newindex` | `value[key] = newValue` | receiver, key, value |
| `__add`, `__sub`, `__mul` | `+`, `-`, `*` | left, right |
| `__div`, `__mod`, `__pow` | `/`, `%`, `^` | left, right |
| `__unm` | unary `-` | operand |
| `__concat` | `..` | left, right |
| `__len` | `#` | operand |
| `__lt`, `__le` | ordered comparison | left, right |

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
local record Key<T> end

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
`function`, has an implicit `self` value, and is emitted on the ordinary method
namespace:

```nupp
local record Counter
    value: number

    function increment(by: number): self
        self.value = self.value + by
        return self
    end
end

local counter = new Counter{value = 0}
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

`metatable<T>` is a compiler-known phantom type. It erases to an ordinary Lua
table and connects the standard metatable functions to their receiver:

```nupp
local record Task end
local task: Task
local mt: metatable<Task> = {__index = {}}

setmetatable(task, mt)
local current: metatable<Task>? = getmetatable(task)
```

Direct metatable literals reject unknown double-underscore keys, catching
mistakes such as `__cal`. Computed tables and metatables assembled inside a
generic registrar remain gradual. `as` retains its usual assertion semantics
and may override the checker.

## Deliberate exclusions

LuaJIT 3.0 gives the bit operators metamethods; the 2.1 backport that Nupp
generates for did not take them, and neither does the `bit` library those
operators are shorthand for. Contracts such as `__band`, `__bor`, `__bxor`,
`__bnot`, `__shl`, `__shr` and `__sar` are therefore rejected, and will
be reconsidered when the runtime dispatches them. `__idiv` is also rejected:
2.1 has no `//` at all, so it lowers to a floored division that dispatches
nothing.

For the same reason, `a += b` where `a` holds a value with an `__add`
contract calls `__add(a, b)` and not the `__add(a, b, true)` LuaJIT 3.0
specifies — the in-place third argument is another part of the backport that
did not come across. Nothing depends on it; a metamethod that ignores its
third argument behaves identically under both.

`__gc` and `__close` are not static operation contracts. Deterministic cleanup
uses affine ownership and `with` scopes instead. `__pairs` is not used to type
`pairs`; LuaJIT's ordinary `pairs` accepts nominal record tables directly.

Declaration-only struct metamethods are rejected. LuaJIT FFI metatypes must be
installed when `ffi.metatype` is called, so an erased promise would leave no
later runtime fulfillment point. Ordinary inline struct methods are supported
through the generated `ffi.metatype` method namespace.

Macro-generated protocol declarations are an `import-tl` concern. Comptime is
deliberately data-only and does not generate declarations, so a translated
macroexp-defined `__len`—such as tecs's `DoubleArray` contract—must be ejected
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
