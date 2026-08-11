# Ownership

A file, a socket, a C allocation — anything that needs exactly one cleanup —
carries that obligation in its type. The checker finds the missing cleanup, the
double free, and the use-after-move before the program runs.

The model is deliberately smaller than Rust's: no named lifetimes, no
typestate, and no borrow checker over arbitrary object graphs. It is aimed at the failures that
happen at a C boundary, and it costs one annotation on the producer.

This page is the working subset. The [ownership reference](../ownership.md) has
the complete model.

## Declaring a resource

`@drop` marks the operation that consumes the resource; `@owned` marks the
function that produces one:

```nupp
local record File
    closed: boolean

    @drop
    function close(self)
        self.closed = true
    end
end

@owned
local function openFile(): File
    return new File(closed = false)
end
```

The annotation, rather than the name, is what makes `close` the drop operation. Bare
`@owned` is accepted only when the result type has exactly one, so the compiler
never has to guess between close, free, flush, and stop.

For a type you do not own, the drop operation can be a free function, and the
producer names it:

```nupp
local record Session
    id: integer
end

@drop
local function closeSession(takes session: Session)
    print("closing", session.id)
end

@owned(closeSession)
local function openSession(id: integer): Session
    return new Session(id = id)
end
```

A drop operation must `takes` its resource. That is what makes it consuming.

## Discharging the obligation

Once you bind an owner, its exact cleanup runs automatically at the binding's
lexical boundary:

```nupp
local f = openFile()
print(f.closed)
-- close runs here, including when code above raises
```

There are three ways to end or transfer the obligation before that boundary.

**Drop it** at the point you choose:

```nupp
local f = openFile()
nupp.drop(f)
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
`takes` parameter — the drop operation, or something that adopts it. `nupp.drop()`
needs a value whose *static type* carries a cleanup list, and a bare `takes`
binding does not have one, so `nupp.drop(session)` there reports NUPP2602 and
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
mutating through one is allowed. Use `exclusive` for a call that needs sole
access because it may invalidate views derived from the value.

For a Nupp function with a body, the checker infers whether a resource
parameter escapes, so a read-only helper needs no annotation at all. Writing
`borrows` anyway pins the contract: a later change that stores the value errors
inside the function instead of silently changing its interface and breaking
callers.

A borrow may be read, mutated, and reborrowed. It may not be returned without a
contract, stored in a table or field, assigned to an outer binding, or captured
by a closure.

## Lexical destruction

Cleanup runs on fallthrough, `return`, `break`, `continue`, a `goto` leaving
the block, and an error raised anywhere inside. Several resources are acquired
left to right and released right to left.

```nupp
do
    local input = openFile()
    local output = openFile()
    print(input.closed, output.closed)
end
```

The bindings remain owners: they may be moved, returned under an owning
contract, or explicitly dropped early. Each successful transfer deactivates
automatic cleanup exactly once.

## Records that hold resources

A record with `owned<T>` fields is itself a resource, and cleanup is
synthesized in reverse field order:

```nupp
local record Bundle
    input: owned<Session>
    output: owned<Session>
end

local bundle = new Bundle(input = openSession(1), output = openSession(2))
nupp.drop(bundle)
```

A custom `@drop` method has to discharge every affine field, and it does
that by calling their drop operation directly:

```nupp
local record Pair
    first: owned<Session>
    second: owned<Session>

    @drop
    function close(self)
        closeSession(self.second)
        closeSession(self.first)
    end
end
```

## Where it stops

`unsafe do` grants permission for pointer operations the checker cannot prove —
raw dereference, `intoRaw`, `fromRaw`, `borrowFrom`. It grants nothing else:
owners still have to be discharged inside one, borrows still cannot escape, and
ordinary lexical cleanup still runs.

The trusted parts are written down. Whether a C function really consumes,
retains, or releases a pointer comes from its declaration, because a header has
no body to inspect. Whether a returned resource is genuinely exclusive is not
observable from a pointer value. Cleanup bodies are not verified. Those are the
auditable edges; everything inside them is checked.

## Next

- [The ownership reference](../ownership.md) — the complete model, C output
  parameters, pinning, and the proved-versus-trusted table.
- [C interop](../c-interop.md) — parameter modes at a C boundary.
