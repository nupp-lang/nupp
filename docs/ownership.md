# Resource ownership, borrowing, and FFI safety

Nupp gives C pointers and ordinary Lua values the same affine resource
model. The checker finds missing cleanup, double consumption, use after move,
dangling lexical borrows, and unproved raw-pointer use before the program runs.
The model is intentionally smaller than Rust's: there are no named lifetimes,
no typestate, no borrow checker for arbitrary object graphs, and no automatic
destruction at ordinary scope exit.

The central rule is:

> Safe code must either prove a resource lifetime or name the exact trusted
> boundary where it stops proving it.

For Nupp bodies, the compiler derives non-escape and transfer effects where
it can. For C declarations and other bodyless interfaces, annotations state
facts that cannot be recovered from a header. `unsafe do` is the explicit
escape hatch for an address or invariant that the checker cannot prove.

## What developers gain

Plain LuaJIT and FFI provide no static distinction among a fresh allocation, a
shared pointer, a pointer retained by C, and an already-freed pointer. Cleanup
conventions live in comments and tests. Nupp turns those conventions into
checked interfaces:

- a returned owner must be disposed or transferred exactly once;
- a `takes` call moves its argument and later use is rejected;
- a derived borrow cannot outlive or be stored away from its source;
- C cannot retain Lua-managed memory without a pinned anchor and a declared
  release;
- a raw pointer cannot be dereferenced, indexed, or passed through an
  uncontracted C parameter in checked code;
- a record containing resources is itself an affine resource;
- a coroutine cannot suspend while a resource or borrow obligation is live;
- cleanup remains deterministic and does not depend on a GC finalizer.

This is useful even in small programs because failures are reported at the
ownership boundary, not later as a leak, double free, stale callback, or
occasional use-after-free.

## Ownership syntax

| Surface | Meaning |
| --- | --- |
| `@owned(cleanup...)` | The first result is a new affine owner with this ordered cleanup list. |
| `@owned` | Use the result type's one inherited `@dispose` operation. |
| `@owned(opaque = true)` | The result is transfer-only; it has no local cleanup operation. |
| `@dispose` | Marks the default operation that consumes a resource. |
| `takes p: T` | The callee accepts and consumes the ownership obligation. |
| `borrows p: T` | Shared, call-duration access; mutation is allowed but escape is not. |
| `exclusive p: T` | Exclusive call-duration access; no other live borrow may overlap it. |
| `retains p: T` | Imported C code keeps a pinned pointer after return. |
| `releases p: T` | Imported C code stops keeping that pinned pointer before return. |
| `T borrows p` | The result remains tied to parameter `p`. |
| `T borrows(a, b)` | The result remains tied to every named source. |
| `owned<T>` | A value carrying one affine discharge obligation. |
| `borrowed<T>` | A non-escaping value tied to another live binding. |
| `pinned<T>` | An affine pointer plus a strong Lua anchor for C retention. |
| `dispose(x)` | Consume `x` and invoke its recorded cleanup list. |
| `borrow(x)` | Create an explicit lexical borrow of `x`. |
| `intoRaw(x)` | In `unsafe`, abandon tracking and return the underlying value. |
| `fromRaw(x, cleanup...)` | In `unsafe`, assert fresh ownership of a raw value. |
| `borrowFrom(raw, source)` | In `unsafe`, assert raw provenance from a named source. |
| `pin(pointer, anchor)` | Bind a managed pointer to the Lua object keeping it valid. |
| `with x = acquire() do ... end` | Deterministically clean an owner on every exit. |
| `unsafe do ... end` | Permit operations whose lifetime proof is deliberately abandoned. |

All ownership syntax is erased or lowered to direct Lua/FFI operations. It
does not change the C ABI and does not install `ffi.gc` finalizers.

## Owned results and deterministic cleanup

An explicit cleanup list is the clearest C-boundary contract:

```nupp
cdef struct widget
   value: int32
end

cdef function widget_stop(borrows value: widget*)
cdef function widget_free(takes value: widget*)

@owned(widget_stop, widget_free)
cdef function widget_new(): widget*

local value = widget_new()
print(value.value)
dispose(value)              -- stop, then free
print(value.value)          -- NUPP2601: use after move
```

Cleanup functions run from left to right. `dispose` takes the owner, so it
cannot run twice. Passing the value to any `takes` parameter discharges the
same obligation without also running the recorded cleanup:

```nupp
cdef function widget_adopt(takes value: widget*)

local value = widget_new()
widget_adopt(value)
dispose(value)              -- NUPP2601: value was moved
```

Every live owner must be discharged along every checked path. The valid exits
are `dispose`, a `takes` call, an ownership-preserving move, an `@owned` return,
or `intoRaw` inside `unsafe`. Ignoring an owned call result is an error.

`@owned` works on Nupp functions and managed Lua values too:

```nupp
local record Channel
   id: integer
end

local function closeChannel(takes channel: Channel)
   print("closing", channel.id)
end

@owned(closeChannel)
local function openChannel(id: integer): Channel
   return new Channel {id = id}
end
```

The checker verifies the body against the declared return contract, but the
claim that the returned external resource is truly exclusive remains a
contract. Exclusivity is not observable from a pointer value.

### Transfer-only owners

Use an opaque owner only when another API must accept the value and local code
has no valid way to destroy it:

```nupp
@owned(opaque = true)
cdef function begin_request(): voidptr

cdef function submit_request(takes request: voidptr)

local request = begin_request()
submit_request(request)     -- valid
-- dispose(request)         -- no cleanup exists
```

Bare `@owned` does not mean opaque. Opaque ownership must be conspicuous.

## Default disposal and Closeable-style interfaces

`@dispose` marks a consuming operation as the default disposer. A bare
`@owned` producer uses it when the result type has exactly one default:

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
   return new File {closed = false}
end

local file = openFile()
dispose(file)               -- calls File:close()
```

A free function can be the default as well, but its resource parameter must be
`takes`:

```nupp
local record Socket end

@dispose
local function closeSocket(takes socket: Socket) end

@owned
local function connect(): Socket return new Socket {} end
```

An interface can declare the contract once and subtypes inherit it:

```nupp
local interface Closeable
   @dispose
   close: function(takes value: self): nil
end

local record File is Closeable
   fd: integer

   function close()
      self.fd = -1
   end
end

@owned
local function openFile(): File return new File {fd = 1} end
```

This gives a Closeable-style abstraction without privileging the name
`close`. The annotation, not spelling, supplies the contract. Bare `@owned` is
rejected when the type has no default or inherits more than one, because the
compiler must never guess whether `close`, `free`, `stop`, or another operation
is correct.

## Parameter effects: `takes`, `borrows`, and `exclusive`

`takes` complements `borrows`: the first transfers the obligation; the second
temporarily sees the value.

```nupp
local function inspect(borrows value: widget*): int32
   return value.value
end

local function destroy(takes value: widget*)
   widget_free(value)
end
```

### Shared borrowing allows mutation

`borrows` is a lifetime and aliasing contract, not a `const` qualifier.
Nupp is normally single-threaded, so mutation through a shared borrow is
allowed when it does not invalidate the identity or lifetime of the resource:

```nupp
local function rename(borrows value: widget*, n: int32)
   value.value = n           -- valid shared mutation
end
```

There is deliberately no `borrowMut` intrinsic and no `exclusive<T>` wrapper.
Exclusive access is a call effect, so the one surface is `exclusive`:

```nupp
local function reset(exclusive value: widget*)
   value.value = 0
end

local value = widget_new()
do
   local view = borrow(value)
   reset(value)              -- error: view overlaps exclusive access
end
dispose(value)
```

Use `exclusive` only for operations that may invalidate derived views, replace
storage, reallocate, or otherwise require call-duration exclusivity. Ordinary
field mutation belongs under `borrows`.

### What is inferred

For a Nupp body, the checker derives whether each resource-shaped
parameter stays within the call. A read-only or stable-mutation helper needs no
annotation:

```nupp
local function inspect(value: widget*): int32
   return value.value
end

local value = widget_new()
inspect(value)               -- inferred borrows
dispose(value)
```

If a parameter is returned without a borrowing-return contract, stored,
captured, or sent through an untyped/indirect call, it is conservatively
escaping. A borrow cannot be passed there:

```nupp
local saved: widget*?

local function stash(value: widget*)
   saved = value
end

local value = widget_new()
do
   local view = borrow(value)
   stash(view)               -- NUPP2603: destination may retain it
end
dispose(value)
```

Explicit `borrows` remains useful because it pins intent and improves error
locality:

```nupp
local saved: widget*?

local function inspect(borrows value: widget*)
   saved = value             -- error here: declared contract is violated
end
```

Without the annotation, adding that store changes the inferred interface and
errors appear at callers that provide borrows. With it, the implementation
change is rejected at the declaration.

Inference cannot originate facts outside a body. `cdef` declarations,
`.d.nupp` overlays, callbacks supplied by another module, and indirect calls
therefore need explicit contracts or conservative treatment. Resource
exclusivity, cleanup choice, and whether C retains an address are never
inferred.

## Lexical borrows and result provenance

`borrow(owner)` is the explicit lexical form. It is useful when a named view
must keep the owner immovable for part of a scope:

```nupp
local value = widget_new()
do
   local view = borrow(value)
   inspect(view)
   dispose(value)            -- error: view is still live
end
dispose(value)               -- valid after the borrow's scope
```

Most calls do not need `borrow(...)`: passing an owner to a `borrows`
parameter and binding a resource inside `with` borrow implicitly.

Borrows may be read, mutated stably, and reborrowed. They may not be returned
without a result contract, stored in a table or field, assigned to an outer
binding, captured by a closure, or moved into an untyped call.

A returned view names its source:

```nupp
local function first(borrows pool: Pool): Item borrows pool
   return pool.items[1]
end
```

The result keeps `pool` borrowed until the result's scope ends. Methods may
use `borrowed<T>` return sugar when the receiver is the only source:

```nupp
function Pool:first(): borrowed<Item>
   return self.items[1]
end
```

Layered resources can be both owned and dependent:

```nupp
@owned(closeTls)
local function openTls(borrows socket: Socket): TLS borrows socket
   return TLS.connect(socket)
end
```

The TLS session must be disposed, and the socket cannot be disposed until that
happens. A result may name several roots:

```nupp
@owned(closePair)
local function pair(borrows left: Resource, borrows right: Resource)
   : Pair borrows(left, right)
   return new Pair {left = left, right = right}
end
```

For functions with bodies, the checker traces returned expressions and
rejects a claimed source it cannot prove. When provenance really travels
through opaque pointer manipulation, assert it at a narrow unsafe boundary:

```nupp
local function recover(borrows source: widget*, raw: widget*)
   : widget* borrows source
   unsafe do
      return borrowFrom(raw, source)
   end
end
```

Bodyless foreign declarations remain trusted contracts because there is no
implementation to inspect.

## Raw pointers and `unsafe`

Raw pointers are allowed, but validity-dependent use requires `unsafe` unless
the value is owned, borrowed, pinned, or passed through a declared lifetime
effect. This is rejected:

```nupp
cdef struct header
   size: uint32
end

local raw = ffi.cast<header*>(address)
print(raw.size)              -- NUPP2604
```

The unchecked operation is explicit:

```nupp
unsafe do
   print(raw.size)
end
```

The same rule covers raw pointer indexing and passing a raw pointer to a plain
C pointer parameter. Give the C parameter a truthful `borrows`, `exclusive`,
`takes`, `retains`, or `releases` contract to use it from checked code.

`unsafe` grants permission for unproved pointer operations. It does **not**
suppress affine obligations or turn off the checker. Owners still must be
discharged, borrows still cannot escape, and `with` still runs cleanup:

```nupp
local value = widget_new()
unsafe do
   local hidden = {value = value} -- still rejected: owner escaped into a table
end
```

### Abandoning and reconstructing tracking

Both directions require `unsafe` because each discards a proof or asserts one:

```nupp
local value = widget_new()
local raw: widget*

unsafe do
   raw = intoRaw(value)                -- obligation deliberately abandoned
   local restored = fromRaw(raw, widget_free)
   dispose(restored)
end
```

`fromRaw` does not discover ownership. It asserts that this exact value is now
exclusive and associates the named cleanup list. A false assertion can still
double-free, so small unsafe blocks are easier to audit than ambient unchecked
FFI code.

## C output parameters

C APIs often return status separately from a pointer written through `T **`.
Nupp declarations can expose that as an ordinary multiple return without
changing the ABI.

### Owned outputs

```nupp
cdef function free(takes value: voidptr)

@owned(out = result, cleanup = free, success = zero)
cdef function posix_memalign(
   out result: voidptr*,
   alignment: uint64,
   size: uint64
): int32

local status, pointer = posix_memalign(16, 4096)
if pointer then
   dispose(pointer)
end
```

The generated call allocates the output slot, passes it in its original C
parameter position, calls C once, and appends the logical output to the Lua
return list. On failure, a conditional output is `nil`.

`success` accepts `always`, `zero`, `nonzero`, or a literal number/string. Use
one annotation per output; multiple outputs preserve both C argument order and
Lua return order. Every owned output needs an explicit `cleanup` name or list.

### Borrowed outputs

A borrowed output must name the input that keeps it valid:

```nupp
@borrowed(out = view, from = store, success = zero)
cdef function store_lookup(
   borrows store: Store*,
   key: cstring,
   out view: Item**
): int32

local status, item = store_lookup(store, "key")
-- store cannot move or be disposed while item is live
```

The `from` parameter must itself be a `borrows` input. This prevents an output
annotation from inventing provenance unrelated to the call.

## C retention and Lua-managed memory

A call-duration borrow is insufficient when C stores an address after return.
Create a `pinned<T>` handle and describe both ends of the retention:

```nupp
cdef function remember_name(retains value: cstring)
cdef function forget_name(releases value: cstring)

local text = "Nupp"
local pointer = ffi.cast<cstring>(text)
local handle = pin(pointer, text)

remember_name(handle)
-- handle.anchor keeps text alive; handle cannot move while retained
forget_name(handle)
```

The generated C call receives `handle.pointer`, not the Lua handle table.
Duplicate retention, release before retention, leaving scope while retained,
or passing an unpinned address is rejected. The `releases` annotation promises
that C stops retaining the pointer before the call returns.

Callbacks are an opaque derivation and require a narrow unsafe construction,
then a pin restores a checked lifetime:

```nupp
unsafe do
   local callback = function() print("called") end
   local pointer = ffi.cast<voidptr>(callback)
   local handle = pin(pointer, callback)
   register_callback(handle) -- declared retains
end
```

## Structured `with` scopes

`with` is the only implicit cleanup construct. It takes each acquisition,
exposes a borrow in the body, and runs recorded cleanup on every exit:

```nupp
with file = openFile() do
   print(file.closed)
end
```

Acquisitions occur left to right and cleanup occurs right to left. Cleanup also
runs for early return, loop control, and errors. Ordinary local owners do not
auto-dispose at scope exit; use `with` when lexical cleanup is intended, and
manual `dispose` or transfer when the exact lifetime matters. If the body and
cleanup both fail, Nupp preserves the body failure as the primary error and
reports the cleanup failure with it.

## Affine records and resource composition

A record with `owned<T>` or `pinned<T>` fields is itself affine:

```nupp
local record Bundle
   input: owned<File>
   output: owned<File>
end

local bundle = new Bundle {
   input = openFile(),
   output = openFile(),
}

dispose(bundle) -- output, then input
```

When no custom default exists, cleanup is synthesized in reverse field
declaration order. Moving an individual affine field out of a live record is
rejected because it would leave a partially initialized owner.

A record may define a custom `@dispose` method. The checker requires that its
body discharge every affine field, and it does that by handing each one to a
`takes` parameter — the field's own disposer:

```nupp
@dispose
local function closeFile(takes file: File) end

local record Bundle
   first: owned<File>
   second: owned<File>

   @dispose
   function close()
      closeFile(self.second)
      closeFile(self.first)
   end
end
```

`dispose(self.second)` does not work here. `dispose` needs a value whose static
type carries a cleanup list, and a field spelled `owned<File>` records the
obligation without recording how to discharge it; that reports `NUPP2602` and
names the fix. The same applies inside a function to a `takes` parameter.

Dynamic collections are different: the checker cannot statically count
aliased table elements. Put the unsafe storage logic behind an owning
container whose checked disposer closes every element. This keeps one audited
unsafe core rather than spreading unchecked ownership through every caller.

## Coroutines

Raw coroutines may be abandoned forever, and LuaJIT has no general static join
or cancellation guarantee. Suspending with a live owner, borrow, pin, retained
handle, or `with` cleanup pending is therefore rejected:

```nupp
local function task()
   local file = openFile()
   coroutine.yield()         -- NUPP2603: cleanup could be abandoned
   dispose(file)
end
```

Yielding with no temporal obligation is valid. Suspending while an obligation
is live is rejected.

## What is proved and what is trusted

| Fact | Derived or checked? | Why |
| --- | --- | --- |
| Local owner moved exactly once | Checked | Visible in Nupp control flow. |
| Borrow stored, captured, returned, or outliving source | Checked | Visible lexical escape and provenance. |
| Resource parameter does not escape a body | Derived conservatively | A property of the body. |
| Explicit `borrows` body honors non-escape | Checked | The declaration pins a verifiable contract. |
| Result expression derives from named parameters | Checked for bodies | Provenance is traceable in the implementation. |
| Result is an exclusive external resource | Trusted | Exclusivity is not observable from its bits. |
| Correct cleanup operation | Trusted | The type does not identify `free` versus `close`. |
| C consumes, retains, or releases a pointer | Trusted | A header has no body or lifetime metadata. |
| C borrowed output derives from the named input | Trusted | The foreign implementation is unavailable. |
| Unsafe pointer manipulation is valid | Trusted locally | `unsafe` explicitly abandons the proof. |

Indirect or untyped calls are conservative. If the checker cannot see a
callee contract, an owner or borrow may not cross it. Convert through
`intoRaw` in `unsafe` only when abandoning the guarantee is intentional.

## Non-goals and limits

- No typestate. The checker tracks whether a resource obligation is live,
  moved, borrowed, retained, or discharged, not arbitrary states such as
  connected/authenticated/committed.
- No prohibition on shared mutation. `borrows` permits stable mutation;
  `exclusive` exists only for operations requiring exclusivity.
- No automatic cleanup for ordinary locals. Determinism is explicit through
  `dispose`, `takes`, or `with`.
- No inference of ownership from names such as `new`, `close`, or `free`.
- No static accounting for a dynamic number of affine table elements.
- No proof of C implementation behavior, allocator pairing, cleanup body
  correctness, or unsafe code.
- No implicit `ffi.gc`. Applications may still use it outside this ownership
  model, but Nupp neither inserts nor depends on it.

The guarantee is consequently precise: safe Nupp code follows its visible
resource contracts. Incorrect foreign contracts and unsafe blocks are the
auditable trusted computing base.

## Choosing the smallest contract

Use this order when binding an API:

1. Mark every fresh owning return or output with `@owned`.
2. Mark destruction/adoption parameters `takes`.
3. Mark call-duration pointer access `borrows`; use `exclusive` only if live
   views could be invalidated.
4. Mark pointers stored by C with matching `retains` and `releases` operations,
   and require callers to pin managed memory.
5. Name the source of every borrowed return or output.
6. Keep raw operations in the smallest possible `unsafe do` block.
7. Prefer `with` for lexical resources and explicit transfer elsewhere.

This surface makes the common path short while preserving annotations exactly
where inference cannot originate or where a stable public contract is useful.
