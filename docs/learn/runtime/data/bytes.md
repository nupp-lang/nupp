---
order: 165
---

# Bytes

Strings hold immutable bytes, arrays hold mutable typed elements, spans borrow
windows over storage, and readers and writers move bytes between sources.
Use `io.Buffer` when bytes arrive or are built a chunk at a time.

```nupp:playground
local buffer = io.Buffer.create()
buffer:put("hello", " ", "world")
assert(#buffer == 11)
assert(buffer:get(6) == "hello ")
assert(buffer:tostring() == "world")
```

## Storage and streams

A string can contain any byte, including zero. Text encodings such as UTF-8
interpret those bytes; the string itself carries no encoding.

`table.Array<T>` holds elements with one physical type. Its managed factories
return ordinary values, while `alloc` returns an owned array. A buffer is
specialized growable byte storage with a read cursor, so `get` and `skip`
consume its unread bytes and `put` appends.

```nupp
local Array = table.Array
local values = Array.bytes(4)
do
    local bytes = values:write()
    bytes[1] = 65
end
assert(values:read()[1] == 65)
```

`Array.scalar(witness, count)` creates a zeroed scalar array, and
`Array.newarray(structValue, count)` creates a zeroed struct array. Select
`"columnar"` with `Array.alloc(ffi.typeof<T>(), count, "columnar")` when
fields need separate contiguous columns. See
[structure-of-arrays.md](structure-of-arrays.md) for that layout.

`io.Reader` and `io.Writer` are stream contracts. `io.Reader.of` opens a string,
span, buffer, immutable byte region, or byte queue; a buffer reader consumes
its read cursor, while a span reader keeps its own position.

```nupp
local buffer = io.Buffer.create("abc")
local reader = buffer:reader()
assert(reader:read(2) == "ab")
reader:close()
assert(buffer:tostring() == "c")
```

## Borrowing and ownership

A span retains its source and checks every index against its count.
[](binary.span.fromstring) lends a read-only `Span<uint8>`; `array:read()`
lends `Span<T>`, and `array:write()` lends the affine `Writable<T>` wrapper
around `WriteSpan<T>`. Functions receiving writable access name
`exclusive bytes: binary.span.ByteWriteSpan` or
`exclusive values: binary.span.WriteSpan<T>`.

```nupp
local buffer = io.Buffer.create("abc")
do
    local bytes = buffer:span()
    assert(bytes[1] == 97)
end
buffer:put("d")
```

The checker blocks conflicting access while a borrow is live. The `Writable<T>`
wrapper owns its exclusive-access token; dropping it ends the borrow without
dropping the storage. See [ownership.md](../ownership/index.md) for ownership
modes and [borrowing.md](../ownership/borrowing.md) for borrow lifetimes.

```nupp:refused
local buffer = io.Buffer.create("abc")
local bytes = buffer:span()
buffer:put("d")
assert(bytes[1] == 97)
```

`Array.alloc` returns an affine array with `Array.destroy` as its cleanup.
An explicit owned type is
`affine(table.Array<int32>, table.Array.destroy)`. Its scope boundary drops
the allocation; managed arrays instead stay alive through their references.
A bare `affine(T)` carries a transfer obligation without a cleanup function.

```nupp
local values: affine(table.Array<int32>, table.Array.destroy) =
    table.Array.alloc(ffi.typeof<int32>(), 2)
do
    local write = values:write()
    write[1] = 42 as int32
end
assert(values:read()[1] == 42)
```

## Index bases

Storage operations use zero-based offsets and counts. Spans use one-based
indexes, and span slices include both endpoints.

| Operation | Position | Extent |
| --- | --- | --- |
| `buffer:readstring(0, 3)` | Storage offset zero | Three bytes |
| `buffer:span(1, 3)` | First unread byte | Through the third unread byte |
| `region:slice(0, 3)` | Region offset zero | Three bytes |
| `view:slice(1, 3)` | First element | Through the third element |
| `writable:splitat(3)` | Boundary after three elements | Left has three elements |

A buffer's typed reads and writes address its physical storage extent.
Consuming bytes changes the read cursor, so `buffer:span()[1]` can refer to a
byte past storage offset zero.

## Reservations

A buffer reservation lends space after its current content. Drop the writable
span before committing how many bytes arrived; dropping the lease without a
commit aborts the reservation.

```nupp
local buffer = io.Buffer.create()
local lease = buffer:reserve(3)
do
    local bytes = lease:span()
    bytes[1], bytes[2], bytes[3] = 65, 66, 67
end
lease:commit(3)
assert(buffer:tostring() == "ABC")
```

## Copies

On LuaJIT, strings are interned, so producing a string copies bytes.
Borrowing a view does not make a string snapshot.

| Operation | Copies bytes on LuaJIT | Retains storage |
| --- | --- | --- |
| `buffer:tostring()` and `buffer:get(n)` | Yes | Result is an independent string |
| `buffer:span()` and `array:read()` | No | Span retains its source |
| `binary.span.fromstring(text)` | No | Span retains the string |
| `io.Reader.of(span)` | No at construction | Reader retains the span |
| `io.Reader.of(region)` | No at construction | Reader retains the immutable region |
| `Bytes:view()` and `Bytes:slice()` | No | View or region retains the block |
| `Bytes:tostring()` | Yes | Result is an independent string |
| `buffer:freeze()` | Through a string into engine storage | Region retains engine storage |

Appending copies the incoming bytes and can also move existing bytes when
capacity grows. Native socket, TLS, and process `readspan` and `writespan`
pass span pointers to their native ABI; `read` still returns a string.

## Shared bytes between workers

`io.Bytes` holds an immutable region of reference-counted engine storage.
It crosses [worker boundaries](../concurrency/workers.md) without copying its
payload and requires the engine host supplied by a stamped binary.

```nupp
local buffer = io.Buffer.create()
buffer:put("payload")
local bytes = buffer:freeze()
local reader = io.Reader.of(bytes)
assert(reader:read(7) == "payload")
reader:close()
```

`freeze` consumes the buffer and preserves only its unread bytes. An HTTP
request can hold a `Bytes` region directly as its body.

`io.Bytes` is transitional: it becomes `string` when workers can share long
strings. Until then, keep it for shared immutable worker payloads and use
ordinary strings for immutable bytes within one lane.
