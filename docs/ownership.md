# Resource ownership, borrowing, and FFI safety

Nupp gives C pointers and ordinary Lua values the same affine resource
model. The checker arranges ordinary lexical cleanup and finds invalid cleanup,
double consumption, use after move,
dangling lexical borrows, and unproved raw-pointer use before the program runs.
The model is intentionally smaller than Rust's: there are no named lifetimes,
no typestate and no borrow checker for arbitrary object graphs.

The central rule is:

> Safe code must either prove a resource lifetime or name the exact trusted
> boundary where it stops proving it.

For Nupp bodies, the compiler derives non-escape and transfer effects where
it can. For C declarations and other bodyless interfaces, annotations state
facts that cannot be recovered from a header. `unsafe do` is the explicit
escape hatch for an address or invariant that the checker cannot prove.

```nupp
local m = {}

local function closeFile(file: LuaFile)
    file:close()
end

@owned(closeFile)
function m.open(path: string): LuaFile
    local file = io.open(path, "r")
    if not file then error("cannot open " .. path) end
    return file
end

function m.readAll(path: string): string
    local file = m.open(path)
    return file:read("*a")
end

return m
```

`@owned` says the result carries a cleanup obligation, and `readAll` discharges
it by letting the local reach its scope boundary. Dropping that obligation
instead is a compile error rather than a leak.

## Guarantees

Plain LuaJIT and FFI provide no static distinction among a fresh allocation, a
shared pointer, a pointer retained by C, and an already-freed pointer. Cleanup
conventions live in comments and tests. Nupp turns those conventions into
checked interfaces:

- a locally droppable owner is destroyed at lexical scope exit unless moved;
- a `takes` call moves its argument and later use is rejected;
- a derived borrow cannot outlive or be stored away from its source;
- C cannot retain Lua-managed memory without a pinned anchor and a declared
  release;
- a raw pointer cannot be dereferenced, indexed, or passed through an
  uncontracted C parameter in checked code;
- a record containing resources is itself an affine resource;
- a raw or unknown coroutine suspension cannot strand a live obligation;
- cleanup remains deterministic and does not depend on a GC finalizer.

This is useful even in small programs because failures are reported at the
ownership boundary, not later as a leak, double free, stale callback, or
occasional use-after-free.

## Ownership syntax

- `@owned(cleanup...)`: the first result is a new affine owner with this ordered
  cleanup list.
- `@owned`: use the result type's one inherited `@drop` operation.
- `@owned(opaque = true)`: the result is transfer-only; it has no local cleanup
  operation.
- `@drop`: marks the default operation that consumes a resource.
- `takes p: T`: the callee accepts and consumes the ownership obligation.
- `borrows p: T`: shared, call-duration access; mutation is allowed but escape
  is not.
- `exclusive p: T`: exclusive call-duration access; no other live borrow may
  overlap it.
- `retains p: T`: imported C code keeps a pinned pointer after return.
- `releases p: T`: imported C code stops keeping that pinned pointer before
  return.
- `T borrows (p)`: the result remains tied to parameter `p`.
- `T borrows (a, b)`: the result remains tied to every named source.
- `T preserves p`: the result transports the exact capability arriving through
  `p`.
- `function(): R borrows (p)`: declare that a closure carries a borrow rooted at
  `p`; closure literals infer omitted borrow captures from their bodies.
- `function(): R takes (p)`: move `p` into an affine, single-shot closure whose
  call or lexical drop discharges the capture.
- `scoped callback: function(...)`: the callee proves a borrow-carrying callback
  cannot escape the call.
- `field: View borrows (source)`: a nominal field is tied to its declared
  sibling root.
- `owned<T>`: a value carrying one affine discharge obligation.
- `borrowed<T>`: a non-escaping value tied to another live binding.
- `pinned<T>`: an affine pointer plus a strong Lua anchor for C retention.
- `nupp.drop(x)`: consume `x` and invoke its recorded cleanup list.
- `nupp.borrow(x)`: create an explicit lexical borrow of `x`.
- `nupp.intoRaw(x)`: in `unsafe`, abandon tracking and return the underlying
  value.
- `nupp.fromRaw(x, cleanup...)`: in `unsafe`, assert fresh ownership of a raw
  value.
- `nupp.borrowFrom(raw, source)`: in `unsafe`, assert raw provenance from a
  named source.
- `nupp.pin(pointer, anchor)`: bind a managed pointer to the Lua object keeping
  it valid.
- `local x = acquire()`: keep a movable owner and destroy it at its lexical
  boundary unless transferred.
- `resources.set(): resources.Set`: a checked dynamic collection that reifies per-owner
  discharge.
- `unsafe do ... end`: permit operations whose lifetime proof is deliberately
  abandoned.

All ownership syntax is erased or lowered to direct Lua/FFI operations. It
does not change the C ABI and does not install `ffi.gc` finalizers.

### Intrinsics live under `nupp`

`nupp.drop`, `nupp.borrow`, `nupp.intoRaw`, `nupp.fromRaw`,
`nupp.borrowFrom`, and `nupp.pin` are compiler-provided operations on the
always-available `nupp` global:

```nupp
local handle = openFile(path)
nupp.drop(handle)
```

The old bare spellings remain aliases. They report the same diagnostics and
lower to the same code, but new code and these examples use `nupp.*` so the
operation's origin is explicit. Either spelling can be shadowed: a local
`nupp` makes `nupp.drop` an ordinary field call, just as a local `drop`
makes `drop(x)` an ordinary call.

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
nupp.drop(value)              -- stop, then free
print(value.value)          -- NUPP2601: use after move
```

Cleanup functions run from left to right. `drop` takes the owner, so it
cannot run twice. Passing the value to any `takes` parameter discharges the
same obligation without also running the recorded cleanup:

```nupp
cdef function widget_adopt(takes value: widget*)

local value = widget_new()
widget_adopt(value)
nupp.drop(value)              -- NUPP2601: value was moved
```

Every live owner must be discharged along every checked path. A locally
droppable ordinary binding is discharged automatically at its lexical scope
boundary, including raised and structured exits. A successful `drop`,
`takes` call, ownership-preserving move, `@owned` return, or `intoRaw` inside
`unsafe` transfers or ends that responsibility and suppresses automatic
cleanup. Ignoring an owned call result is still an error. Transfer-only owners
remain errors unless an explicit terminal consumes them.

`@owned` works on Nupp functions and managed Lua values too:

A bodyless API may attach the same producer contract directly to a
function-valued record or interface field:

```nupp
local interface Files
   @owned(closeFile)
   open: function(path: string): File
end
```

```nupp
local record Channel
   id: integer
end

local function closeChannel(takes channel: Channel)
   print("closing", channel.id)
end

@owned(closeChannel)
local function openChannel(id: integer): Channel
   return new Channel(id = id)
end
```

The checker verifies the body against the declared return contract, but the
claim that the returned external resource is truly exclusive remains a
contract. Exclusivity is not observable from a pointer value.

Free cleanup functions are resolved where `@owned` is declared. A private
cleanup therefore crosses a module boundary with the owner contract without
becoming a public module field. The declaring module registers its function
object under a compiler-owned key; a consuming module resolves that key on its
first discharge and then calls the cached function directly. Loading the
consumer before the producer is safe because resolution is lazy, and obtaining
an owner necessarily ran the producer first.

### Cleanup context is owner state

A resource cannot secretly carry its pool, allocator, arena, or parent handle:
ownership annotations erase, and cleanup later needs a runtime place from which
to read that context. Make the pair an explicit nominal owner and put the
context in its fields. A custom `@drop` method can then pass every required
argument without allocating a closure per owner:

```nupp
local record Connection end

local record Pool
   release: function(self: Pool, takes value: Connection)
end

local record PoolConnection
   pool: Pool
   connection: owned<Connection>

   @drop
   function close(self)
      self.pool:release(self.connection)
   end
end

@owned
local function adopt(pool: Pool, takes connection: Connection): PoolConnection
   return new PoolConnection(pool = pool, connection = connection)
end
```

The `release` contract consumes the connection, so Nupp can check this cleanup
without `unsafe`. The wrapper remains visible in the API because its pool is
real runtime state; Nupp does not hide it in a side table or attach a finalizer.

### Transfer-only owners

Use an opaque owner only when another API must accept the value and local code
has no valid way to destroy it:

```nupp
@owned(opaque = true)
cdef function begin_request(): voidptr

cdef function submit_request(takes request: voidptr)

local request = begin_request()
submit_request(request)     -- valid
-- nupp.drop(request)         -- no cleanup exists
```

Bare `@owned` does not mean opaque. Opaque ownership must be conspicuous.

## Default drop and Closeable-style interfaces

`@drop` marks a consuming operation as the default drop operation. A bare
`@owned` producer uses it when the result type has exactly one default:

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

local file = openFile()
nupp.drop(file)               -- calls File:close()
```

A free function can be the default as well, but its resource parameter must be
`takes`:

```nupp
local record Socket end

@drop
local function closeSocket(takes socket: Socket) end

@owned
local function connect(): Socket return new Socket() end
```

An interface can declare the contract once and subtypes inherit it:

```nupp
local interface Closeable
   @drop
   close: function(takes value: self): nil
end

local record File is Closeable
   fd: integer

   function close(self)
      self.fd = -1
   end
end

@owned
local function openFile(): File return new File(fd = 1) end
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
   local view = nupp.borrow(value)
   reset(value)              -- error: view overlaps exclusive access
end
nupp.drop(value)
```

Use `exclusive` only for operations that may invalidate derived views, replace
storage, reallocate, or otherwise require call-duration exclusivity. Ordinary
field mutation belongs under `borrows`.

### Inference

For a Nupp body, the checker derives whether each resource-shaped
parameter stays within the call. A read-only or stable-mutation helper needs no
annotation:

```nupp
local function inspect(value: widget*): int32
   return value.value
end

local value = widget_new()
inspect(value)               -- inferred borrows
nupp.drop(value)
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
   local view = nupp.borrow(value)
   stash(view)               -- NUPP2603: destination may retain it
end
nupp.drop(value)
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

`nupp.borrow(owner)` is the explicit lexical form. It is useful when a named
view must keep the owner immovable for part of a scope:

```nupp
local value = widget_new()
do
   local view = nupp.borrow(value)
   inspect(view)
   nupp.drop(value)            -- error: view is still live
end
nupp.drop(value)               -- valid after the borrow's scope
```

Most calls do not need `nupp.borrow(...)`: passing an owner to a `borrows`
parameter borrows it implicitly for the call.

Borrows may be read, mutated stably, and reborrowed. They may not be returned
without a result contract, stored in a table or field, assigned to an outer
binding, captured by a closure, or moved into an untyped call.

A returned view names its source:

```nupp
local function first(borrows pool: Pool): Item borrows (pool)
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
local function openTls(borrows socket: Socket): TLS borrows (socket)
   return TLS.connect(socket)
end
```

The TLS session must be dropped, and the socket cannot be dropped until that
happens. A result may name several roots:

```nupp
@owned(closePair)
local function pair(borrows left: Resource, borrows right: Resource)
   : Pair borrows(left, right)
   return new Pair(left = left, right = right)
end
```

For functions with bodies, the checker traces returned expressions and
rejects a claimed source it cannot prove. When provenance really travels
through opaque pointer manipulation, assert it at a narrow unsafe boundary:

```nupp
local function recover(borrows source: widget*, raw: widget*)
   : widget* borrows (source)
   unsafe do
      return nupp.borrowFrom(raw, source)
   end
end
```

Bodyless foreign declarations remain trusted contracts because there is no
implementation to inspect.

### Capability-preserving generics

Payload type parameters do not erase the capability beside a value. A result
relation names the input slot whose exact cleanup order, opacity, roots, pin,
retention state, and affine identity move to the result:

```nupp
local id: function<T>(value: T): T preserves value

local file = id(openFile("input"))
nupp.drop(file)
```

Visible identity and narrowing bodies infer this relation. Bodyless interfaces
state it explicitly. `assert` and `setmetatable` use it, so narrowing an
optional owner does not lose its producer-specific cleanup. A generic body
that duplicates, stores, or abandons its argument remains callable for plain
values but rejects an affine instantiation.

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

### Foreign calls without lifetime contracts

When a C API lacks those annotations, the wrapper still has to retain its
allocator context, but its cleanup must put the trusted boundary at the call:

```nupp
cdef struct allocator end
cdef struct block end
cdef function ctx_free(ctx: allocator*, value: block*)

local struct Allocation
   ctx: allocator*
   value: block*

   @drop
   function close(self)
      -- ctx_free has no lifetime annotations, so Nupp has no proof for this call.
      unsafe do
         ctx_free(self.ctx, self.value)
      end
   end
end

@owned
local function adopt(ctx: allocator*, value: block*): Allocation
   return new Allocation(ctx, value)
end
```

This FFI-shaped pair is a `struct` because its C pointers have a fixed layout
and need no Lua-table features. A `record` would also be valid when table
identity, dynamic fields, or GC-managed state are useful.

`unsafe` grants permission for unproved pointer operations. It does **not**
suppress affine obligations or turn off the checker. Owners still must be
discharged, borrows still cannot escape, and lexical cleanup still runs:

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
   raw = nupp.intoRaw(value)                -- obligation deliberately abandoned
   local restored = nupp.fromRaw(raw, widget_free)
   nupp.drop(restored)
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
   nupp.drop(pointer)
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
-- store cannot move or be dropped while item is live
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
local handle = nupp.pin(pointer, text)

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
   local handle = nupp.pin(pointer, callback)
   register_callback(handle) -- declared retains
end
```

## Automatic lexical cleanup

An ordinary owned local runs its recorded cleanup at its lexical boundary:

```nupp
do
   local file = openFile()
   print(file.closed)
end
```

Acquisitions occur left to right and cleanup occurs right to left. Cleanup also
runs for early return, loop control, and errors. The local remains movable;
moving, returning, or explicitly dropping it deactivates automatic cleanup
exactly once. Use `drop` for early release and an explicit terminal operation
when successful completion has protocol meaning. If the body and cleanup both
fail, Nupp preserves the body failure as the primary error and reports the
cleanup failure with it.

Every cleanup function and `@drop` body must be non-suspending. A foreign or
bodyless cleanup makes this trusted promise; a visible body is checked from its
transitive effect summary.

## Affine records and resource composition

A record with `owned<T>` or `pinned<T>` fields is itself affine:

```nupp
local record Bundle
   input: owned<File>
   output: owned<File>
end

local bundle = new Bundle(
   input = openFile(),
   output = openFile()
)

nupp.drop(bundle) -- output, then input
```

When no custom default exists, cleanup is synthesized in reverse field
declaration order. Individual affine fields may move out. Their path-sensitive
state becomes moved, independent fields remain accessible, whole-record methods
are refused, and synthesized drop skips only fields proven moved. Assigning
the same exact affine contract back reinitializes the field.

A record may define a custom `@drop` method. The checker requires that its body
discharge every affine field, and it does that by handing each one to a `takes`
parameter, which is the field's own drop operation:

```nupp
@drop
local function closeFile(takes file: File) end

local record Bundle
   first: owned<File>
   second: owned<File>

   @drop
   function close(self)
      closeFile(self.second)
      closeFile(self.first)
   end
end
```

`nupp.drop(self.second)` does not work here. `drop` needs a value whose static
type carries a cleanup list, and a field spelled `owned<File>` records the
obligation without recording how to discharge it; that reports `NUPP2602` and
names the fix. The same applies inside a function to a `takes` parameter: its
erased payload does not carry the producer-specific cleanup witness, so an
untouched `takes` parameter is not automatically destroyed. Its body must use
an explicit matching terminal, transfer, or owning return.

Nominal records may also retain declared borrows:

```nupp
local record Cursor
   source: Buffer
   bytes: Bytes borrows (source)
end
```

Construction proves `bytes` derives from the sibling `source`; the source field
cannot be replaced while the dependent field is live. Anonymous and dynamic
table storage remains rejected.

### Dynamic resource sets

`resources.Set` is the audited container for a runtime number of owners:

```nupp
local resources = require("nupp.resources")

do
   local group = resources.set("request")
   local input = group:adopt(resources.openFile("in"))
   local output = group:adopt(resources.openFile("out"))
   copy(input, output)
end
```

`adopt` moves the owner and returns a borrow tied to the set. The compiler
reifies that producer's exact cleanup references only at this call. Set cleanup
runs registrations in reverse order, attempts every cleanup step, and reports
primary and suppressed failures. `remove` deletes one registration and returns
the original capability exactly once. An opaque owner needs an explicit
matching terminal consumer as the second argument.

### Checked spans

`nupp.span` provides `ByteSpan` and affine `ByteWriteSpan` views. They retain a
root, carry a runtime element count, bounds-check every index and slice, and
keep an invalidation barrier live for a write span until `commit` or scope exit.
Direct pointer or variable-length C-array indexing has no runtime bound and is
rejected even when its lifetime is rooted. A fixed C array rejects a literal
index that is statically out of range and inserts a runtime check for every
non-literal index. Conversion, unchecked indexing, and unknown pointer
arithmetic remain inside the smallest possible `unsafe` block.

## Coroutines

Raw coroutines may be abandoned forever, and LuaJIT has no general static join
or cancellation guarantee. Suspending with a live owner, borrow, pin, or
retained handle is therefore rejected:

```nupp
local function task()
   local file = openFile()
   coroutine.yield()         -- NUPP2603: cleanup could be abandoned
   nupp.drop(file)
end
```

Yielding with no temporal obligation is valid. A checked suspension operation
may cross obligations because it either blocks to completion or transfers a
park to an installed handler whose cancellation must resume and unwind it.
Lexically placing raw `coroutine.yield` inside a handled region does not bless
it. Handler shutdown cancels every park before succeeding, and cleanup still
cannot suspend while cancellation is discharging another obligation.

Reading an owner or borrow from an ordinary closure captures a tracked borrow.
The closure remains copyable, but its callable capability is borrowed and its
exact roots travel as value-flow provenance. Consequently it cannot outlive a
root, enter anonymous storage, or be returned without a declared relation.

A `takes (...)` clause instead moves the named owners into the closure. That
makes the closure affine and single-shot: calling it consumes the closure, and
leaving it uncalled lets lexical cleanup drop both the closure and its captures.
An ordinary copyable closure may borrow an owner, but it may not own one.

A scoped callback parameter is the synchronous transport rule for a
borrow-carrying closure. The visible callee must prove it invokes the callback
without storing, returning, retaining, or forwarding it to an unknown target.

## Proof and trust

```
 Fact                                                    Derived or checked?       Why
 ──────────────────────────────────────────────────────  ────────────────────────  ─────────────────────────────────────────────────────
 Local owner moved exactly once                          Checked                   Visible in Nupp control flow.
 Borrow stored, captured, returned, or outliving source  Checked                   Visible lexical escape and provenance.
 Resource parameter does not escape a body               Derived conservatively    A property of the body.
 Explicit borrows body honors non-escape                 Checked                   The declaration pins a verifiable contract.
 Result expression derives from named parameters         Checked for bodies        Provenance is traceable in the implementation.
 Result is an exclusive external resource                Trusted                   Exclusivity is not observable from its bits.
 Correct cleanup operation                               Trusted                   The type does not identify free versus close.
 C consumes, retains, or releases a pointer              Trusted                   A header has no body or lifetime metadata.
 C borrowed output derives from the named input          Trusted                   The foreign implementation is unavailable.
 Unsafe pointer manipulation is valid                    Trusted locally           unsafe explicitly abandons the proof.
 A handled park eventually resumes or cancels            Trusted handler contract  Scheduler behavior is not derivable from a Lua value.
```

Indirect or untyped calls are conservative. If the checker cannot see a
callee contract, an owner or borrow may not cross it. Convert through
`intoRaw` in `unsafe` only when abandoning the guarantee is intentional.

## Non-goals and limits

- No typestate. The checker tracks whether a resource obligation is live,
  moved, borrowed, retained, or discharged, not arbitrary states such as
  connected/authenticated/committed.
- No prohibition on shared mutation. `borrows` permits stable mutation;
  `exclusive` exists only for operations requiring exclusivity.
- No automatic terminal choice for opaque or multi-terminal protocols. Ordinary
  locals auto-destroy only when their exact producer cleanup is known.
- No inference of ownership from names such as `new`, `close`, or `free`.
- No arbitrary affine table storage; dynamic ownership is confined to
  `resources.Set`.
- No proof of C implementation behavior, allocator pairing, cleanup body
  correctness, or unsafe code.
- No implicit `ffi.gc`; safe code also rejects attaching it to owned, borrowed,
  pinned, or retained values because that would create a second cleanup path.

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
7. Use ordinary locals for lexical owners and explicit operations for early
   release or meaningful terminals.

This surface makes the common path short while preserving annotations exactly
where inference cannot originate or where a stable public contract is useful.

Run `nupp ownership-audit --json [file...]` to enumerate foreign pointer
parameters/results, every explicit unsafe assertion region, and each recognized
raw memory operation inside one. The report is an inventory of the trusted
surface, not a claim that the foreign implementation was verified.
Add `--regions` to include deterministic automatic-cleanup region identities,
activation and cleanup order, and their protected lowering class.

## Diagnostics

- **NUPP2601**: a resource is used after it was moved, or discharged twice.
- **NUPP2602**: a value is dropped whose static type records the obligation
  without recording how to discharge it, such as an `owned<T>` field or a
  `takes` parameter.
- **NUPP2603**: a borrow outlives what it borrows from, by escaping into a
  destination that may retain it or across a suspension point.
- **NUPP2604**: a raw pointer is used where the checker cannot prove the
  address is valid. `unsafe do` is where that proof stops.

## Next

- [Ownership](start/ownership.md): the working subset, with the annotations a
  caller actually writes.
- [Calling C safely](c-interop.md): what these contracts mean at the FFI
  boundary they were built for.
