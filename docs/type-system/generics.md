# Generics

```nupp
local function firstOr<T>(items: {T}, fallback: T): T
    if #items > 0 then
        return items[1]
    end
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

A binder ending in `...` is a type-pack parameter. It preserves a heterogeneous
sequence rather than choosing one element type:

```nupp
local function forward<A...>(...: A...): A...
    return ...
end

local type Adapter<A..., R...> = function(A...): R...
local type PairAdapter = Adapter<(number, string), (boolean, integer)>

local interface Source<R...>
    read: function(self): R...
end

local record Values<R...> is Source<R...>
    read: function(self): R...
end
```

Ordinary binders precede pack binders. Explicit pack arguments use parentheses
to delimit one pack from the next; those parentheses are type-pack syntax, not a
tuple allocation. Pack parameters work uniformly on aliases, records,
interfaces, and functions. See [Type packs](packs.md) for list adjustment,
correlation, and ownership rules.

A computed tuple or array can supply a pack tail with `unpackof`:

```nupp
local type Arguments<Kind> = match Kind when 'pair' then {string, number} when 'flag' then {boolean,} else any
end

local function apply<Kind is string>(kind: Kind, ...: unpackof Arguments<Kind>): string
    return kind
end

apply('pair', 'x', 1)
apply('flag', true)
```

The inverse operation is available in tuple match patterns. A final
`unpackof infer Tail` captures every slot after the fixed prefix, preserving a
heterogeneous tuple (and binding `{never}` when that suffix is empty):

```nupp
local type DropFirst<Values> = match Values when {infer _, unpackof infer Tail} then Tail else never
end
```

Expansion happens after inference and finite type reduction. A tuple contributes
fixed slots, an array contributes a homogeneous rest tail, and an undecidable
result becomes `...any`. The trailing comma distinguishes the one-slot tuple
`{T,}` from the array `{T}`. A concrete result of any other shape is rejected at
the call.

Computed tuples can be assembled recursively with the same operator inside a
tuple: `{Head, unpackof Tail}`. When `Tail` reduces to a tuple, its slots are
appended; `{never}`, the array that cannot contain an element, contributes zero
slots. This permits a recursive reducer to build a parameter list without an
arbitrary arity ladder.

`typeerror<Message>` is the failure result for a type-level computation. Its
message must become concrete before a consumer such as `unpackof` needs the
result. The consumer reports that message directly instead of exposing the
intermediate type used to carry it:

```nupp
local type Checked<T> = match T when string then {T,} else typeerror<`expected string, got ${T}`>
end
```

## Constraints use `is`

```nupp:static
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

## Refinements

An interface may carry a `matches` block, which names the runtime test that
decides whether a value is one of these. `x is T` compiles to that test:

```nupp
local interface Shape
    kind: string
end

local interface Circle is Shape
    kind: string
    radius: number

    satisfies |self| -> self.kind == "circle"
end
```

```lua
-- `s is Circle` becomes
(type(s) == "table" and s.kind == "circle")
```

**Only an interface.** A record is identified by the metatable `new` stamps and
a struct by its ctype, so both already answer `is` exactly. A refinement beside
either would be a second answer to a settled question, and which answer `is R`
gave would depend on whether a body happened to carry one. An interface has no
runtime table at all, so this is the only identity it can have.

That is also what lets an interface answer `is` for values this program did not
build, such as a table off a decoder or anything an untyped library returned.
Such a value never received a metatable, so nothing else could identify it.

The test has to run wherever `is` is written, so it reads the declaration's own
fields through `self` and nothing else: comparisons against literals, `type()`
tests, and `and` / `or` / `not`. A call, arithmetic, or a name from outside the
subject is **NUPP2122**, and so is a refinement that always answers the same
way: always true identifies every value, and always false leaves the type
uninhabited.

A subject that is not a plain name is evaluated once and handed to the test,
since a refinement may read it more than once. Reaching through a field guards
the step before it with `?.`, because the test runs against values that are not
of the type yet, so `matches self.a.b.c == "x" end` compiles to `s.a?.b?.c ==
"x"`.

A declaration is held to the refinements of the interfaces it declares. `record
C is Shape` is a claim the checker proves, and Shape's refinement is what `is
Shape` runs, so fields that provably fail it are **NUPP2122**. The alternative
is a value the checker calls a `Shape` and `is` calls otherwise.

## Inference at a call site

Type arguments come from the arguments:

```nupp:static
print(firstOr({1, 2, 3}, 0)) -- T = integer
```

Inference is structural unification over parameters against argument types. It
sees through arrays, tuples, maps, unions, shapes, function types, pointers,
and nominal applications, and it strips ownership wrappers first.

Three behaviors are worth knowing:

- **A binder appearing twice unions the two arguments** rather than failing or
  picking the more specific one.
- **`any` and `nil` arguments do not bind a parameter.** They leave it open.
- **An unbound parameter substitutes to `any`**, which keeps a partly-inferred
  call gradual instead of wrong.

A `T?` parameter subtracts the concrete members from the argument, so the
residue binds. That is how `assert` is typed:

```nupp:static
-- assert: function<T>(v: T?, msg: any?): T
local name: string? = maybeName()
local sure = assert(name) -- sure is string
```

## There is no explicit type argument at a call site

`f<number>(x)` parses as two comparisons, exactly as it does in Lua:

```nupp
local n = id < number > (1)
-- NUPP2003: cannot compare boolean and 1 with '>'
```

Type arguments appear in *type* position, as in `Box<number>` and `a.b.Map<K,
V>`, and at the six FFI intrinsics, which are special-cased in the grammar:

```nupp:static
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

`Box<number>` is one type everywhere. Instantiations are memoized, and the cache
is populated before members are filled in, so a self-referential generic
terminates.

Generic nominals are **covariant** in every argument, so `Box<integer>` is
accepted where `Box<number>` is wanted. Like array covariance, this is
deliberately unsound for mutable contents and chosen for compatibility.

## `self`

`self` is a per-declaration type parameter, rebound to the actual receiver:

```nupp
local record Counter
    value: number

    function increment(self, by: number): self
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

```nupp:static
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

`T` is inferred from `Key<T>` for both the read and the write.

## Diagnostics

- **NUPP2003**: an operator is applied to types it does not accept, which an
  unbounded type parameter reports before a bound admits the operation.
- **NUPP2116**: a type argument violates its bound, checked where the generic is
  instantiated.
- **NUPP2122**: a refinement cannot be enforced.

## Next

- [packs.md](packs.md): variadic parameters and correlated results.
- [type-level-computation.md](type-level-computation.md): computing a type from a type parameter.
