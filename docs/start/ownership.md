# Ownership

A file, a socket, a C allocation — anything that needs exactly one cleanup —
carries that obligation in its type. The checker finds the missing cleanup, the
double free, and the use-after-move before the program runs.

The model is deliberately smaller than Rust's: no named lifetimes, no
typestate, no borrow checker over arbitrary object graphs, and no automatic
destruction when an ordinary scope ends. It is aimed at the failures that
happen at a C boundary, and it costs one annotation on the producer.

This page is the working subset. The [ownership reference](../ownership.md) has
the complete model, and [resource scopes](../with.md) covers `with` in detail.

## Declaring a resource

Two annotations. `@dispose` marks the operation that consumes the resource, and
`@owned` marks the function that produces one:

```nupp
local record File
    closed: boolean

    @dispose
    function close()
        self.closed = true
    end
end

@owned
local function openFile(): File
    return File{closed = false}
end
```

The annotation, rather than the name, is what makes `close` the disposer. Bare
`@owned` is accepted only when the result type has exactly one, so the compiler
never has to guess between close, free, flush, and stop.

For a type you do not own, the disposer can be a free function, and the
producer names it:

```nupp
local record Session
    id: integer
end

@dispose
local function closeSession(takes session: Session)
    print("closing", session.id)
end

@owned(closeSession)
local function openSession(id: integer): Session
    return Session{id = id}
end
```

A disposer must `takes` its resource. That is what makes it consuming.

## Discharging the obligation

Once you hold an owner, every path has to get rid of it exactly once:

```nupp
local f = openFile()
-- error: NUPP2603: owned value "f" leaves scope without being consumed,
-- disposed, returned, or converted with intoRaw
```

There are four ordinary ways out.

**Dispose it** at the point you choose:

```nupp
local f = openFile()
dispose(f)
```

**Scope it**, which is the usual answer:

```nupp
with f = openFile() do
    print(f.closed)
end
```

**Hand it on** to a parameter that takes it:

```nupp
local function enqueue(takes session: Session)
    closeSession(session)
end

local s = openSession(1)
enqueue(s)
```

**Return it** from a function that is itself `@owned`.

Inside a function, a `takes` parameter is discharged by passing it to another
`takes` parameter — the disposer, or something that adopts it. `dispose()`
needs a value whose *static type* carries a cleanup list, and a bare `takes`
binding does not have one, so `dispose(session)` there reports NUPP2602 and
names the fix.

## Borrowing

A `borrows` parameter gets access for the duration of the call without taking
responsibility:

```nupp
local function inspect(borrows session: Session)
    print(session.id)
end

local s = openSession(1)
inspect(s)
closeSession(s)
```

`borrows` is a lifetime and aliasing contract rather than a `const` qualifier —
mutating through one is allowed. Use `inout` for a call that needs exclusive
access because it may invalidate views derived from the value.

For a Nupp function with a body, the checker infers whether a resource
parameter escapes, so a read-only helper needs no annotation at all. Writing
`borrows` anyway pins the contract: a later change that stores the value errors
inside the function instead of silently changing its interface and breaking
callers.

A borrow may be read, mutated, and reborrowed. It may not be returned without a
contract, stored in a table or field, assigned to an outer binding, or captured
by a closure.

## What `with` does

```nupp
with f = openFile() do
    print(f.closed)
end
```

The owner moves into a slot your code cannot name, and the visible binding is a
borrow of it. Because the owner is unreachable, the compiler always knows
cleanup is still owed, and no runtime "already closed" flag is needed.

Cleanup runs on fallthrough, `return`, `break`, `continue`, a `goto` leaving
the body, and an error raised anywhere inside. Several resources share one
scope; they are acquired left to right and released right to left.

```nupp
with
    input = openFile(),
    output = openFile()
do
    print(input.closed, output.closed)
end
```

`with` is the only construct that cleans up on your behalf. An ordinary local
owner is not released because its scope ended — forgetting is an error, which
is the part `try`-with-resources and context managers leave out.

## Records that hold resources

A record with `owned<T>` fields is itself a resource, and cleanup is
synthesized in reverse field order:

```nupp
local record Bundle
    input: owned<Session>
    output: owned<Session>
end

local bundle = Bundle{input = openSession(1), output = openSession(2)}
dispose(bundle)
```

A custom `@dispose` method has to discharge every affine field, and it does
that by calling their disposer directly:

```nupp
local record Pair
    first: owned<Session>
    second: owned<Session>

    @dispose
    function close()
        closeSession(self.second)
        closeSession(self.first)
    end
end
```

## Where it stops

`unsafe do` grants permission for pointer operations the checker cannot prove —
raw dereference, `intoRaw`, `fromRaw`, `borrowFrom`. It grants nothing else:
owners still have to be discharged inside one, borrows still cannot escape, and
`with` still runs its cleanup.

The trusted parts are written down. Whether a C function really consumes,
retains, or releases a pointer comes from its declaration, because a header has
no body to inspect. Whether a returned resource is genuinely exclusive is not
observable from a pointer value. Cleanup bodies are not verified. Those are the
auditable edges; everything inside them is checked.

## Next

- [The ownership reference](../ownership.md) — the complete model, C output
  parameters, pinning, and the proved-versus-trusted table.
- [Resource scopes](../with.md) — `with` ordering, failure behavior, and cost.
- [C interop](../c-interop.md) — parameter modes at a C boundary.
