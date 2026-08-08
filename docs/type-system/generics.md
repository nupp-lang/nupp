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

The grammar also carries a `where` refinement on a declaration. Nothing checks
the expression, so writing one is **NUPP2122** rather than a constraint:

```nupp
local record Odd where 1 + 1 == 3
    n: integer
end
-- NUPP2122: a 'where' refinement is not implemented, so this constraint
-- is not checked
```

Express the constraint as a type where one fits — a union of literals, or a
bound like the ones above.

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
