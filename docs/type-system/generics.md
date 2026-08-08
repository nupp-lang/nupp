# Generics

```nupp
local function firstOr<T>(items: {T}, fallback: T): T
    if #items > 0 then return items[1] end
    return fallback
end
```

Type parameters go on functions, function types, and declarations.

```nupp
local record Box<T>
    value: T
end

local type Handler<E> = function(event: E): boolean
local mapper: function<A, B>(xs: {A}, f: function(A): B): {B}
```

## Constraints use `is`

```nupp
local function start<T is Callable>(task: T): T
    return task()
end

local record Registry<T is Named>
    entries: {T}
end
```

Inside the body, the parameter's fields, methods, and metamethods are read from
its bound, with `self` specialized back to the parameter.

Bounds are checked where a generic is instantiated, not inside the subtyping
relation. Violating one is NUPP2116:

```
NUPP2116: type argument string for T: string is not a number
```

An `any` argument skips the bound check.

## `where` refinements

A declaration may carry a `where` refinement, which names the runtime test that
decides whether a value is one of these. `x is T` compiles to that test:

```nupp
local interface Shape
    kind: string
end

local record Circle is Shape where self.kind == "circle"
    kind: string
    radius: number
end
```


```lua
-- `s is Circle` becomes
(type(s) == "table" and s.kind == "circle")
```

This is what lets a declaration answer `is` when its values were not built by
this program — a table off a decoder, or anything an untyped library returned.
A record without one is identified by the metatable `new` stamps, which such a
value never received. An interface has no runtime table at all, so a refinement
is the only identity it can have; without one, `is` on an interface cannot be
compiled.

The test has to run wherever `is` is written, so it reads the declaration's own
fields through `self` and nothing else: comparisons against literals, `type()`
tests, and `and` / `or` / `not`. A call, arithmetic, or a name from outside the
subject is **NUPP2122**, and so is a refinement that always answers the same
way — always true identifies every value, always false leaves the type
uninhabited. A struct cannot carry one either: `ffi.istype` already answers
exactly.

A subject that is not a plain name is evaluated once and handed to the test,
since a refinement may read it more than once. Reaching through a field guards
the step before it with `?.`, because the test runs against values that are not
of the type yet — `where self.a.b.c == "x"` compiles to `s.a?.b?.c == "x"`.

## Inference at a call site

Type arguments come from the arguments:

```nupp
print(firstOr({1, 2, 3}, 0))     -- T = integer
```

Inference is structural unification over parameters against argument types. It
sees through arrays, tuples, maps, unions, shapes, function types, pointers,
and nominal applications, and it strips ownership wrappers first.

Three behaviours are worth knowing:

- **A binder appearing twice unions the two arguments** rather than failing or
  picking the more specific one.
- **`any` and `nil` arguments do not bind a parameter.** They leave it open.
- **An unbound parameter substitutes to `any`**, which keeps a partly-inferred
  call gradual instead of wrong.

A `T?` parameter subtracts the concrete members from the argument, so the
residue binds. That is how `assert` is typed:

```nupp
-- assert: function<T>(v: T?, msg: any?): T
local name: string? = maybeName()
local sure = assert(name)        -- sure is string
```

## There is no explicit type argument at a call site

`f<number>(x)` parses as two comparisons, exactly as it does in Lua:

```nupp
local n = id<number>(1)
-- NUPP2003: cannot compare boolean and 1 with '>'
```

Type arguments appear in *type* position — `Box<number>`, `a.b.Map<K, V>` — and
at the six FFI intrinsics, which are special-cased in the grammar:

```nupp
local p = ffi.new<Point>()
local q = ffi.cast<Point*>(address)
local t = ffi.typeof<Point>()
local ok = ffi.istype<Point>(v)
local n = ffi.sizeof<Point>()
local a = ffi.alignof<Point>()
```

When you need to pin a parameter that inference will not reach, annotate the
binding instead:

```nupp
local empty: {string} = {}
```

## Instantiation

`Box<number>` is one type everywhere — instantiations are memoized, and the
cache is populated before members are filled in, so a self-referential generic
terminates.

Generic nominals are **covariant** in every argument, so `Box<integer>` is
accepted where `Box<number>` is wanted. Like array covariance, this is
deliberately unsound for mutable contents and chosen for compatibility.

## `self`

`self` is a per-declaration type parameter, rebound to the actual receiver:

```nupp
local record Counter
    value: number

    function increment(by: number): self
        self.value = self.value + by
        return self
    end
end
```

A subtype inheriting a `self`-returning contract gets its own type back rather
than the declaring type. This is what makes an inherited
`metamethod __call: function(self, ...): self` return the concrete record.

## Generic metamethods

A metamethod contract may carry its own type parameters, which lets a typed key
determine the result of an index:

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

`T` is inferred from `Key<T>` for both the read and the write.
