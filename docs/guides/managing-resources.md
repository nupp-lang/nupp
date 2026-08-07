# Managing resources

Files, sockets, native handles, and similar values need exactly one cleanup.
Nupp tracks that obligation as ownership and makes the normal path concise
with `with` scopes.

## Give the type a default disposer

For a Nupp-managed resource, mark the consuming cleanup operation with
`@dispose` and the producer with `@owned`:

```nupp
local record Session
   closed: boolean

   @dispose
   function close()
      self.closed = true
   end
end

@owned
local function openSession(): Session
   return Session{closed = false}
end
```

The annotation, not the method name, makes `close` the default disposer. Bare
`@owned` is accepted only when the result type has exactly one default, so the
compiler never guesses between operations such as close, free, flush, or
stop.

## Prefer a `with` scope

Acquire the resource directly in a scope:

```nupp
with session = openSession() do
   print(session.closed)
end
```

Inside the body, `session` is a borrow. On every exit, Nupp consumes the owner
and invokes its cleanup. This is the preferred shape when a resource belongs
to one lexical operation.

Keep acquisition close to the scope that owns it. Avoid storing a resource in
a broad mutable variable before entering `with`; a narrow lifetime makes both
the code and diagnostics easier to understand.

## Transfer ownership deliberately

A `takes` parameter receives the cleanup obligation. A `borrows` parameter
gets call-duration access without taking it:

```nupp
local function inspectSession(borrows session: Session)
   print(session.closed)
end

local function enqueueSession(takes session: Session)
   dispose(session)
end

local session = openSession()
inspectSession(session)
enqueueSession(session)
```

After `enqueueSession`, the caller cannot use or dispose `session` again.
Prefer `borrows` unless the callee genuinely becomes responsible for cleanup;
ownership transfer should be visible at the function boundary.

## Dispose explicitly when control changes hands

Use `dispose(value)` when a scope is not the right shape:

```nupp
local session = openSession()
inspectSession(session)
dispose(session)
```

Every checked path must discharge the owner by disposing it, passing it to a
`takes` parameter, returning it from an `@owned` function, or making an
explicit unsafe raw transfer. Ignoring an owned result is an error.

For cleanup order, multiple resources, failure behavior, coroutine rules, C
output parameters, retained pointers, and the complete affine model, read the
[ownership reference](../ownership/index.html#structured-with-scopes).
