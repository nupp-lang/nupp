`nupp.io` is bytes: storage for them, and the readers and writers that move
them. Reach for it when a program needs a growable buffer, an immutable
snapshot of one, or a parser that works the same over a buffer, a file and an
HTTP response body.

```nupp:playground
local bytes = nupp.io.newBuffer("hello")
local reader = bytes:newReader()
assert(reader:read(5) == "hello")
```

A buffer holds its bytes in a LuaJIT FFI array, so a program that uses one adds
no native dependency. `Reader` and `Writer` are interfaces rather than the
concrete things that satisfy them, which is what lets code written against the
contract work over any of them without knowing which it has.

The rest of what `io` means is a module of its own, because each has a luacase
name and so can have one. See [path.md](io/path.md) for filesystem names,
[uri.md](io/uri.md) for resource identifiers, [files.md](io/files.md) for the
filesystem itself, [](nupp.io.process) for running a child process, and
[](nupp.io.http) for the asynchronous HTTP client. Keeping them apart is what
lets a program that wants a byte buffer carry a byte buffer rather than every
provider behind the name.

The last three move their bytes through the `Reader` and `Writer` contracts on
this page, so a parser written against byte I/O reads a file, a child's output,
or a response body without knowing which it has.

Every value here is an owner. `close` is safe to call repeatedly and answers
whether the thing it was writing into was still open, so a caller that cares can
tell a clean finish from a destination that went away first. `isReleased`
reports that state without changing it.

## Buffers

`newBuffer()` creates an empty growable buffer. A string supplies initial
bytes; an integer reserves capacity without changing the length.

```nupp
local bytes = nupp.io.newBuffer("hello")
bytes:setString("!", bytes:length())
assert(bytes:getString() == "hello!")
```

Buffer offsets are zero-based, as they are wherever a count is an offset into
storage rather than a position in a Lua string. See [Byte
positions](../../concepts/standard-library.md#byte-positions) for the rule and
where the other convention applies.

`getString(offset, count)` copies a range. `setString` overwrites from an
offset and grows the buffer as needed, filling any gap with zero bytes. `clear`
sets the length to zero without discarding capacity, and `resize` truncates or
zero-fills:

```nupp
local bytes = nupp.io.newBuffer("hello")
bytes:ensureCapacity(4096)
assert(bytes:capacity() >= 4096)
bytes:resize(3)
assert(bytes:getString() == "hel")
```

Capacity is the allocation, not a recorded number. Growing at least doubles it,
so appending through a writer costs amortized constant time per byte and
`capacity()` reports bytes that are actually held. `ensureCapacity` reserves at
least the minimum asked for.

`close()` releases the buffer's storage, and an operation on a released buffer
raises rather than answering a reason.

## Byte views

`view(offset, count)` returns an immutable snapshot, not a mutable alias into
the buffer. It remains valid if the source buffer changes or closes:

```nupp
local buffer = nupp.io.newBuffer("header-body")
local header = buffer:view(0, 6)
buffer:clear()
assert(header:getString() == "header")
header:close()
```

A view can make a smaller view, open its own snapshot reader, report its byte
length, copy to a string, and be closed. Its offsets are zero-based like a
buffer's. The data and UTF-8 modules accept views, which is what keeps those
APIs from being coupled to a mutable buffer.

## Readers

A `nupp.io.Reader` is a forward-only byte source. `newStringReader(text)` reads
a string; `buffer:newReader()` reads a snapshot of the buffer's current
contents.

```nupp
local reader = nupp.io.newStringReader("abcdef")
assert(reader:read(2) == "ab")

local destination = nupp.io.newBuffer()
assert(reader:readInto(destination, 0, 3) == 3)
assert(destination:getString() == "cde")
assert(reader:read(8) == "f")
assert(reader:read(8) == "") -- EOF
```

`read(count)` returns at most `max(1, count)` bytes, so zero and negative
counts still make progress. It returns an empty string at EOF and nil with a
reason after close. `readInto(buffer, offset, count)` returns zero at EOF and
reads 64 KiB when given no count. `transferTo(writer)` copies the entire
remaining source and returns the byte count.

## Writers

`buffer:newWriter()` clears the buffer and returns a forward-only writer
targeting it.

```nupp
local destination = nupp.io.newBuffer()
local writer = destination:newWriter()
assert(writer:write("prefix:"))

local payload = nupp.io.newBuffer("body")
assert(writer:writeFrom(payload) == 4)
assert(writer:flush())
assert(destination:getString() == "prefix:body")
```

`write` answers a boolean; `writeFrom` and `writeView` answer the byte count.
All three answer a reason when the writer is closed or the destination was
released, and writing a buffer into itself is rejected. `flush` does nothing
for memory and is part of the contract so that a later file or socket writer
implements the same interface.

## Typed scalars

A reader and a writer move bytes. `newScalarReader` and `newScalarWriter` add
the missing piece, a sized integer or float landing on those bytes without an
`ffi.cast` at every call site.

```nupp
local writer = nupp.io.newScalarWriter()
writer:writeUint32(1447383632 as uint32):writeFloat64(1.5)

local reader = nupp.io.newScalarReader(assert(writer:buffer()))
assert(reader:readUint32() == (1447383632 as uint32))
assert(reader:readFloat64() == 1.5)
assert(reader:atEnd())
```

Every write answers the writer, so calls chain. A short read raises rather than
answering a reason, which is the one place this pair departs from the reader
and writer contracts above: a scalar either landed whole or the source was not
what the format said, and there is no partial value to hand back.

::: deepdive Host byte order
Both directions read and write host-endian, the only order LuaJIT ships, so
that is the honest default. A format fixed to one byte order casts and swaps
explicitly, and there are no LE and BE variants here until something needs
them. Adding a second set without a caller would double the surface and leave
half of it untested.
:::

### Scalar sources

`newScalarReader` takes whatever holds the bytes. A string, a `ByteView` or a
`Buffer` is read from a copy taken there and then, so `remaining()` knows the
count:

```nupp
local reader = nupp.io.newScalarReader("\1\2\3\4")
assert(reader:remaining() == 4)
```

A `Reader` is consumed as it goes, which is what lets a file or an HTTP body be
read a field at a time. It cannot say how much is left, so `remaining()`
answers nil and `atEnd()` is the question to ask instead.

### Scalar destinations

`newScalarWriter` appends to a `Buffer`, keeping what that buffer already
holds, or writes through a `Writer`. Given nothing it starts a buffer of its
own, which `buffer()` hands back:

```nupp
local destination = nupp.io.newBuffer("header:")
nupp.io.newScalarWriter(destination):writeUint8(33 as uint32)
assert(destination:getString() == "header:!")
```

A writer pointed at somebody else's `Writer` answers nil from `buffer()`, since
the bytes are already gone.

## Byte queues

A `string.buffer` is a byte queue: `put` appends to the back and `get` consumes
from the front. `newScalarReader` accepts one directly, so bytes assembled
there are read without copying everything in it first, and the queue's own
`get` stays usable over the same bytes.

```nupp
local buffer = require("string.buffer")

local queue = buffer.new()
queue:put("header:")
queue:put("!")

local reader = nupp.io.newScalarReader(queue)
assert(reader:readBytes(7) == "header:")
assert(queue:tostring() == "!")
assert(reader:readUint8() == (33 as uint8))
```

Reading drains the queue, and `remaining()` reports what it still holds.
`newQueueReader` is the same bridge one layer down: it answers an ordinary
`Reader` over the queue, for `transferTo`, `readInto`, and everything else that
contract already covers.

```nupp
local buffer = require("string.buffer")

local destination = nupp.io.newBuffer()
local queue = buffer.new()
queue:put("payload")
assert(nupp.io.newQueueReader(queue):transferTo(destination:newWriter()) == 7)
assert(destination:getString() == "payload")
```

Neither takes the queue over. Nothing here frees or closes it, and one read to
empty leaves an empty queue rather than a released one.

::: seealso
- [files.md](io/files.md) for the same contracts over a file on disk
- [path.md](io/path.md) for filesystem names rather than file contents
- [standard-library.md](../../concepts/standard-library.md) for the errors,
  ownership and byte-position conventions every facility shares
:::
