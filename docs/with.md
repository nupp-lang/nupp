# Explicit resource scopes

A file, a socket, a C allocation, or any other value produced by an `@owned`
function carries a cleanup obligation that the checker will not let you drop.
`with` is the construct that discharges it for you:

```nupp
local function closeFile(file: LuaFile)
    file:close()
end

@owned(closeFile)
function files.open(path: string): LuaFile
    local file = io.open(path, "r")
    if not file then error("cannot open " .. path) end
    return file
end

with file = files.open("input.txt") do
    print(file:read("*a"))
end
```

The resource is released when the block ends — on fallthrough, on `return`,
on loop control, on a `goto` leaving the body, and on an error raised anywhere
inside. `with` is the *only* place Nupp closes something on your behalf. An
ordinary local owner is not closed because its scope ended; the checker
requires an explicit `dispose`, a `takes` call, or an owning return instead.
Forgetting both `with` and an explicit disposition is a compile error, which
is the part Python's context managers and Java's try-with-resources do not
have.

The complete ownership model — `@owned`, `takes`, `borrows`, pins, raw
pointers, affine records — is in [ownership.md](ownership.md). This page is
about the scope construct itself: how it is written, what it does with the
value, what order things happen in, and what happens when something fails.

## Writing one

One resource:

```nupp
with channel = openChannel() do
    channel:send(message)
end
```

Several, sharing one scope:

```nupp
with
    input = openFile("input.bin", "rb"),
    output = openFile("output.bin", "wb")
do
    output:write(input:read("*a"))
end
```

The line break is formatting, not syntax. The formatter keeps the whole header
on the `with` line when it fits, and otherwise puts one binding per line with
`do` on its own line.

A binding may carry a type annotation. It describes the underlying resource;
the name is still a borrow of it:

```nupp
with file: LuaFile = openFile(path) do
    -- file is borrowed<LuaFile> here
end
```

`with` is a contextual keyword, so it remains usable as an ordinary variable
name. At statement position it is recognized only when the next tokens are a
name followed by `=` or `:`.

Each acquisition is a single-value context: its first result must be a
non-optional owner with at least one known cleanup function, and any further
results are discarded as in ordinary Lua. An optional owner has to be narrowed
before it can be acquired:

```nupp
local maybe = maybeOpen()
if maybe then
    with file = maybe do
        use(file)
    end
end
```

`assert` will not do that for you — it does not carry ownership metadata
through, so `nupp.dispose(assert(maybeOwned()))` reports NUPP2602.

An acquisition can also be an owner you already hold, which moves it:

```nupp
local channel = openChannel()

with active = channel do
    use(active)
end

-- channel was moved at entry and is not usable here
```

## What the binding is

The owner itself is moved into a slot your code cannot name. The visible
binding is a borrow of it for the length of the block, which is what makes the
scope safe to reason about: because the owner is unreachable, the compiler
always knows cleanup is still owed, and no runtime "already closed" flag is
needed.

Inside the body you may call methods on the binding and pass it to parameters
that borrow. You may not:

- dispose it or pass it to a `takes` parameter;
- return it;
- store it in a table, a field, or anything longer-lived;
- capture it in a closure or a coroutine; or
- assign something else to the binding.

If the value needs to outlive the block, `with` is the wrong tool. Use the
manual controls instead:

```nupp
local channel = openChannel()
manager:add(channel)       -- `add` takes it

local other = openChannel()
nupp.dispose(other)             -- closed at this exact point

local returned = openChannel()
return returned            -- the enclosing function is @owned(...)
```

## Layered resources

A producer can borrow one resource and hand back another that keeps holding
it, by declaring the tie:

```nupp
@owned(tlsFlush, tlsFree)
local function openTls(borrows socket: Socket): TLS borrows socket
```

The result is an ordinary owner that still has to be discharged; what the
annotation adds is that the socket cannot be released while the session holds
it:

```nupp
local socket = openSocket()
local tls = openTls(socket)
nupp.dispose(socket)                -- rejected: the session still holds it
nupp.dispose(tls)                   -- releases the borrow
nupp.dispose(socket)                -- now allowed
```

Which is what lets both layers live in one scope, since reverse cleanup order
already releases them in the order the borrow requires:

```nupp
with socket = openSocket(), tls = openTls(socket) do
    use(tls)
end
```

A later acquisition may borrow an earlier one for the duration of its own call
without any annotation; the annotation is only needed when the *result* keeps
holding it. Either way the tie travels with the value and does not survive
being stored: a borrow still may not be put in a table or a field.

A composite owner that takes its lower layer remains the simpler choice when
the layers never need separate names.

## Order

Acquisitions run left to right, and each one is registered before the next
begins, so a later failure still cleans up everything already acquired.

Resources close in reverse acquisition order. Within one resource, its cleanup
functions run in the order the annotation lists them:

```nupp
@owned(channelStop, channelClose)
local function openChannel(): Channel
    -- ...
end

@owned(logFlush, logClose)
local function openLog(): Log
    -- ...
end

with
    channel = openChannel(),
    log = openLog()
do
    use(channel, log)
end
```

runs `logFlush`, `logClose`, `channelStop`, `channelClose`.

Only the last cleanup step for a resource may consume it, which is checked;
an earlier step that took ownership would free a value the remaining steps
still use.

## Failure

Cleanup runs for normal fallthrough, `return`, `break`, `continue`, a `goto`
leaving the body, and an error raised during acquisition or the body. An error
raised through the scope from anywhere is covered, since the whole region is
protected.

Every resource and every cleanup step is attempted even after one of them
raises. When more than one thing fails, the errors are ordered rather than
merged:

- a body or acquisition failure stays primary, and cleanup failures are
  attached to it as context;
- if the body succeeded, the first cleanup failure becomes primary and later
  ones are attached to that.

A single failure is rethrown exactly as it was raised, with its original error
value and position. Several are raised as a resource-scope failure whose
`primary` field holds the first error and whose `suppressed` array holds the
rest in order; `tostring` renders the primary error followed by the cleanup
context.

As in ordinary Lua, a `goto` may not jump *into* the scope of a binding.

## Coroutines

Yielding from inside a `with` block is rejected. The block is not left
dynamically by a yield, but a raw coroutine can stay suspended forever, and
the cleanup would then never run. A borrow from a scope also cannot be
captured by a coroutine. Moving the owner into the coroutine transfers the
obligation instead, and then the coroutine has to account for it.

This is the same rule the rest of the resource model applies to suspension;
see [ownership.md](ownership.md#coroutines).

## Cost

LuaJIT has no `finally`, no stack destructors, and no to-be-closed locals, so
running cleanup after an arbitrary error needs a protected region. Each
executed `with` enters one, not one per resource. Cleanup calls are
individually protected on the way out, so a failing cleanup cannot prevent the
rest.

Where the region starts depends on which lowering applies. With several
bindings, or a body that captures from around it, the acquisitions run inside
the region alongside the body, so a later acquisition failing still cleans up
everything already acquired. In the shared form below — one resource, a body
that captures nothing — the acquisition is emitted ahead of the region, which
is equivalent because a failure there has acquired nothing to release.

That boundary is deliberately visible in the source as `with`. Ordinary owner
tracking, `dispose`, and `takes` do not introduce one, so a function that
happens to acquire a resource is not silently wrapped.

A scope whose body captures nothing from around it and holds a single resource
is compiled into a region built once and reused, rather than a fresh closure
per execution. That matters more than it sounds: building a closure is
`NYI: bytecode FNEW`, which aborts the enclosing trace, so a loop around a
`with` would never compile. Measured on LuaJIT 2.1/arm64 over two million
iterations:

```
 body                              per-execution   shared   speedup
 ────────────────────────────────  ─────────────  ───────  ────────
 resource does not escape                  468ms     12ms       39x
 resource escapes through cleanup          478ms     90ms      5.3x
```

The second row is the honest figure; the first is flattered by allocation
sinking once the loop compiles. Both describe a hot repeated scope, which is
the shape `with` suits least — where resources are coarse the difference
closes, and a scope that does capture enclosing state stays correct and
measurably unchanged. `bench/ownership.lua` measures the surrounding
trade-offs, including `ffi.gc`.

## Diagnostics

```
 Code       Meaning
 ─────────  ────────────────────────────────────────────────────────────
 NUPP2610   An acquisition is not a non-optional owned value.
 NUPP2611   An acquired owner has no known cleanup functions.
 NUPP2612   A borrow escapes by return, storage, or capture.
 NUPP2613   A binding is reassigned.
 NUPP2614   A visible borrow is disposed or passed to `takes`.
 NUPP2615   A cleanup signature is invalid, or a non-final step takes.
 NUPP2616   A returned owner retains a borrow of an input.
 NUPP2617   A `goto` enters a scope and bypasses acquisition.
 NUPP2618   A borrowing return names a parameter the function takes.
 NUPP2619   A borrowed result or output has no provable source.
```

Free cleanup functions are resolved where the owner contract is declared and
linked under a compiler-owned key. They may therefore remain private when the
owner crosses a module boundary; `with` does not re-resolve their source
spelling in the consumer.

`NUPP2610` through `NUPP2617` belong to resource scopes. The last two are
borrow-provenance codes and are also raised away from a `with`, wherever a
result claims to borrow from something.

Yielding inside a `with` is `NUPP2603`, the general live-obligation code,
rather than one of these.

Where it can, a diagnostic points at both the acquisition and the invalid use.
The live-owner diagnostic outside a scope (NUPP2603) may offer a `with` or a
`dispose` as a fix, but only when the rewrite preserves control flow rather
than guessing what was meant.

`unsafe do` does not switch any of this off. An acquisition still needs a
statically known cleanup list, and the escape rules still apply; `unsafe`
grants permission for unproved pointer and provenance operations only.

## Editor rewrites

The language server offers both directions of the transformation, and refuses
rather than guesses where they are not equivalent.

**Wrap in a `with` scope** turns an acquisition and its disposal into a scope.
It is a `refactor.rewrite` on any owned local, and the quick fix for the
live-owner diagnostic (NUPP2603) on one that has no disposal at all. The
header is rewritten in place — `local` becomes `with`, ` do` is appended — so
a type annotation and the acquisition expression survive exactly as written.
The scope closes at the `dispose` when there is one, and otherwise at the end
of the enclosing block, which is where the obligation already came due. It is
not offered for an owner the block returns, because `with` would close it on
the way out and hand back a dead value, nor for a transfer-only owner
(`@owned(opaque = true)`), because the scope would have nothing to call.

**Unwrap a `with` scope** restores the manual controls. Acquisitions come back
in the order they were written and disposals in the reverse of it, matching
the scope's own cleanup order. It is not offered for a body that leaves by
`return`, `break`, `continue`, or `goto`: `with` closes its owners on those
paths and a trailing `dispose` would not, so the rewrite would silently change
what the program does. A `return` inside a nested function body is not such a
path and does not block it.

## Tooling

- The parser and CST preserve `with` headers and trivia losslessly, and the
  formatter owns the single-line versus multiline decision.
- Hover on a binding shows the borrowed type and the owning acquisition, and
  go-to-definition on cleanup metadata reaches the cleanup function.
- Semantic tokens distinguish the visible borrow from an ordinary local.
- A function's ordered `@owned` cleanup list is part of its exported interface
  fingerprint, so changing it rechecks dependents. A `with` inside a body is
  local detail and changes no interface by itself.

## What is deferred

`with` covers lexical resource lifetimes and nothing wider. Named lifetimes,
borrows stored in fields, ownership-preserving generic pass-throughs such as
an ownership-aware `assert`, destructuring acquisition, and structured child
coroutines borrowing from a parent scope are not part of it. The reasoning and
the current state of each are recorded in `plans/with.md` in the repository,
under "open questions".
