# Byte buffers, readers and writers

`nupp.io` supplies in-memory byte I/O without requiring a stream framework. A buffer
holds its bytes in a LuaJIT FFI array, so using it adds no native dependency. Files and
processes build on the same reader and writer contracts when their native features are
selected; sockets and general asynchronous streams remain separate future layers.

## Buffers

`newBuffer()` creates an empty growable buffer. A string supplies initial bytes; an
integer reserves capacity without changing the length.

```nupp
local bytes = nupp.io.newBuffer("hello")
bytes:setString("!", bytes:length())
assert(bytes:getString() == "hello!")

bytes:ensureCapacity(4096)
assert(bytes:capacity() >= 4096)
bytes:resize(3)
assert(bytes:getString() == "hel")
```

Buffer offsets are zero-based. `getString(offset, count)` copies a range. `setString`
overwrites from an offset and grows the buffer as needed; a gap is filled with zero
bytes. `clear` sets the length to zero without discarding capacity. `resize` truncates or
zero-fills.

Capacity is the allocation, not a recorded number. Growing at least doubles it, so
appending through a writer costs amortized constant time per byte and `capacity()`
reports bytes that are actually held. `ensureCapacity` reserves at least the minimum
asked for.

`close()` releases the buffer, is safe to call repeatedly, and makes later operations
raise. `isReleased()` reports that state.

| Member | Purpose |
| --- | --- |
| `length()`, `capacity()` | Inspect logical and reserved byte counts. |
| `clear()`, `resize(length)` | Remove bytes, truncate, or zero-extend. |
| `ensureCapacity(minimum)` | Reserve without changing logical length. |
| `getString(offset?, count?)` | Copy all bytes or a zero-based range. |
| `setString(bytes, offset?)` | Overwrite and grow from a zero-based offset. |
| `view(offset?, count?)` | Retain an immutable snapshot range. |
| `newReader()`, `newWriter()` | Open directional in-memory I/O. |
| `isReleased()`, `close()` | Inspect or release ownership. |

## Byte views

`view(offset, count)` returns an immutable snapshot, not a mutable alias into the
buffer. It remains valid if the source buffer changes or closes:

```nupp
local buffer = nupp.io.newBuffer("header-body")
local header = buffer:view(0, 6)
buffer:clear()
assert(header:getString() == "header")
header:close()
```

A view can make a smaller view, open its own snapshot reader with `newReader`, report
its byte length, copy to a string, and be closed. Data and UTF-8 functions accept views
so callers can avoid coupling those APIs to a mutable buffer.

`ByteView` provides `newReader`, `length`, `getString`, `view`, `isReleased`,
and `close`. Its `view` offsets are zero-based like Buffer offsets.

## Readers

A `nupp.Reader` is a forward-only byte source. `newStringReader(text)` reads a string;
`buffer:newReader()` reads a snapshot of the buffer's current contents.

```nupp
local reader = nupp.io.newStringReader("abcdef")
assert(reader:read(2) == "ab")

local destination = nupp.io.newBuffer()
assert(reader:readInto(destination, 0, 3) == 3)
assert(destination:getString() == "cde")
assert(reader:read(8) == "f")
assert(reader:read(8) == "") -- EOF
```

`read(count)` returns at most `max(1, count)` bytes, so zero and negative counts still
make progress. It returns an empty string at EOF and `nil, reason` after close.
`readInto(buffer, offset, count)` returns zero at EOF. Its default count is 64 KiB.
`transferTo(writer)` copies the entire remaining source and returns the byte count.

| Reader member | Result |
| --- | --- |
| `read(count)` | `string?, reason?` |
| `readInto(buffer, offset?, count?)` | `integer?, reason?` |
| `transferTo(writer)` | `integer?, reason?` |
| `close()` | `boolean, reason?` |

## Writers

`buffer:newWriter()` clears the buffer and returns a forward-only writer targeting it.

```nupp
local destination = nupp.io.newBuffer()
local writer = destination:newWriter()
assert(writer:write("prefix:"))

local payload = nupp.io.newBuffer("body")
assert(writer:writeFrom(payload) == 4)
assert(writer:flush())
assert(destination:getString() == "prefix:body")
```

`write` returns a boolean. `writeFrom` and `writeView` return the byte count. All return
a reason when closed or when the destination was released. Writing a buffer into itself
is rejected. `flush` is a no-op for memory but is part of the common writer contract,
allowing a later file or socket writer to implement the same interface.

| Writer member | Result |
| --- | --- |
| `write(bytes)` | `boolean, reason?` |
| `writeFrom(buffer, offset?, count?)` | `integer?, reason?` |
| `writeView(view, offset?, count?)` | `integer?, reason?` |
| `flush()` | `boolean, reason?` |
| `close()` | `boolean, reason?` |

For filesystem names rather than file contents, see [`nupp.io.Path`](path-uri.md#paths).

## Child processes

`nupp.io.process` starts a child without exposing descriptors, platform handles, or
signals. Reaching the module selects the native process provider and the suspension
runtime it needs.

```nupp
local process = require("nupp.io.process")

local child, spawnReason = process.new({
   args = {"cc", "--version"},
   stdin = "null",
})
assert(child, spawnReason)
local result, communicateReason = child:communicate()
assert(result, communicateReason)
assert(result:succeeded(), result.errorOutput)
print(result.output)
assert(child:close())
```

`args[1]` is the program and the remaining entries are its arguments. `cwd` changes
the child's directory. `env` overlays inherited variables unless `clearEnv` starts
from an empty environment. Standard streams default to `"pipe"` and may instead be
`"inherit"` or `"null"`; stderr alone may be `"stdout"` to share stdout's actual
destination. `timeoutMs` is measured from spawn, not from the first wait.

`communicate({input?, maxOutputBytes?})` is the safe whole-process operation: it feeds stdin while
draining stdout and stderr together, closes stdin to deliver EOF, and waits for the
exit. Doing those operations sequentially can deadlock when a child fills one output
pipe while waiting for more input.

The concrete `Reader` and `Writer` satisfy the shared completion-oriented
`nupp.Reader` and `nupp.Writer` contracts and also expose the nonblocking `poll` and
`offer` operations needed by that combined drain. `asReader` and `asWriter` borrow the
same records through their shared interfaces; they do not allocate or duplicate the
native handle. The owning `Process` retains and eventually destroys that handle, so a
borrow may not outlive it.

Every wait is contextual. With no
[suspension handler](start/suspension-handlers.md) installed, it sleeps in the
platform readiness wait. Under a scheduler handler, the same call parks the
current task while the scheduler keeps running. Ready operations do neither.

[Suspension](start/suspension.md) explains how the same ordinary call takes
those paths and how several waits compose with `all`, `race`, or `batch`.

`Process.close()` is idempotent and is also its lexical `@drop`: it attempts every
stream release, terminates a child still running, waits for it to finish, and releases
the child handle. An `Exit` reports `exitCode`, `killed`, and `timedOut`; `succeeded()`
is true only for an ordinary zero exit.
