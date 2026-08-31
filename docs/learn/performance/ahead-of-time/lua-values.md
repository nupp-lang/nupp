---
order: 632
---

# Building Lua values ahead of time

The Lua-builder AOT entry constructs fresh tables and strings while keeping
unfinished values rooted on the VM stack. The compiler selects this ABI when
an admitted function returns an ordinary Lua value.

An admitted body that constructs or returns a Lua table or string is entered as
a registered Lua C closure instead of through FFI:

```nupp
@aot
local function rows(count: integer): {number}
    local result = table.new(count, 0)
    for index = 1, count do
        result[index] = index * 2
    end
    return result
end
```

With `aot = "off"`, that is unchanged ordinary Nupp. With `require`, the
resolved `table.new` becomes `lua_createtable`, writes to the fresh unpublished
table use the public raw-set API, and one native call returns the completed
ordinary Lua value. Table literals infer their array and hash capacities.

## Builder subset

The shipped builder subset admits fresh table literals, exact
`table.new(arrayCapacity, hashCapacity)`, primitive number, boolean, string and
`nil` values, string arguments, nested fresh tables, numeric and string-key
writes, numeric reads from those fresh tables, rooted-string length, byte and
substring operations, concatenation, structured control flow, and a final
return:

```nupp
@aot
local function summary(name: string, count: integer): {string: any}
    return {
        name = name,
        count = count,
        limits = {low = 0, high = count},
        ok = count > 0,
    }
end
```

An append-only local such as `answer = answer .. piece` is recognized from the
ordinary source and lowered to the Lua C API's buffered-string operations. It
does not require `nupp.data.valuebuilder` calls or a second AOT-only body.

It rejects reads from arguments or published tables, mutation of either,
metatables, dynamic calls, callbacks, userdata, cycles, and arbitrary Lua
execution. A table that arrived from outside is refused at the parameter rather
than at its first access:

```nupp
@aot
local function extend(target: {number}, count: integer): {number}
    for index = 1, count do
        target[index] = index
    end
    return target
end
```

```text
src/rows.nupp:2:31: aot: parameter type {number} is not admitted
```

Every live constructed object stays in an absolute Lua stack slot across
allocating calls. Generated code uses the public Lua 5.1 API for allocation,
barriers, strings, stack checks, and errors, and does not address LuaJIT
collector objects. Dynamic capacities and array indexes are checked for
integral, nonnegative C-API range before use, and strings are ordinary
Lua-owned strings rather than shared-memory views.

## Tree materialization

Pointer-free parsers may return the native-endian tree representation consumed
by `nupp.data.valuebuilder.materializeTree`. An AOT builder lowers that resolved
call to one bounds-checked C traversal: source and arena blobs remain rooted
strings, tables are presized from authored child counts, raw writes keep
barriers correct, and source slices or validated backslash and Unicode recipes
become Lua-owned strings.

```nupp
local valuebuilder = require("nupp.data.valuebuilder")

--- @raises when the blobs do not describe a well-formed tree
@aot
local function decode(nodes: string, links: string, source: string, null: any): any
    return valuebuilder.materializeTree(nodes, links, source, 1, null)
end
```

This is a general codec and AST construction boundary. It does not expose
`lua_State`, stack indexes, or collector objects, and the ordinary module
implementation is the `aot = "off"` oracle.

## Streaming construction

Streaming parsers can avoid that representation entirely. The resolved
`nupp.data.valuebuilder` stream API starts with `new(nullValue)`, opens arrays
or objects with an estimated capacity, adds keys and primitive values, closes
each container, and publishes exactly one root with `finish`.

```nupp
local valuebuilder = require("nupp.data.valuebuilder")

--- Reads `source` as fixed-width integer fields and returns them as an array.
@aot
local function decodeFields(
    source: string,
    count: uint32,
    width: uint32,
    nullValue: any
): any
    local builder = valuebuilder.new(nullValue)
    valuebuilder.openArray(builder, count)
    local cursor: uint32 = 0
    local length = valuebuilder.length(source)
    while cursor < length do
        valuebuilder.integerSlice(builder, source, cursor, width)
        cursor = nupp.math.u32.add(cursor, width)
    end
    valuebuilder.close(builder)

    return valuebuilder.finish(builder)
end
```

Every capacity, offset and length is a `uint32`, and so is the arithmetic that
advances the cursor. An ordinary binary64 number reaching one of these is
refused rather than promoted, because the offsets address the parser's own bytes
and a fractional one is not an offset.

`string`, `key`, and `numberSlice` take zero-based ranges of a rooted string, so
generated code copies or converts directly into the final Lua value without an
intermediate substring. `byte`, `word`, and `length` let the same AOT entry
parse rooted byte strings, where `word` reads a native-endian uint32 at a
zero-based word index. `depth`, `kind`, and `count` expose only the current
construction-frame metadata an iterative parser needs.

The stream handle cannot be returned, reassigned, stored, or passed to ordinary
calls; only the resolved builder operations admit it. Generated code keeps
unfinished tables and object keys on the VM stack, checks stack growth at every
opening, performs barriers through raw-set calls, and uses no native heap
storage that could leak across a Lua allocation failure.

## Bounded scratch storage

`newSized(nullValue, maxDepth, stringCapacity)` replaces the default 1,024-frame
bound with authored frame storage and reserves a bound for transformed strings.
The first 16 frames stay inline, and deeper streams lazily spill to dynamically
allocated, Lua-rooted storage. The byte storage is allocated lazily on the first
escaped string and reused; publication still performs exactly one copy into a
normal Lua string.

`newByteScratch`, `scratchByte`, `setScratchByte`, and `resetByteScratch` give
the same bounded storage to other codecs, while `stringScratch` and `keyScratch`
publish a checked initialized range directly. A string assembled byte by byte
and published once looks like this:

```nupp
local valuebuilder = require("nupp.data.valuebuilder")

--- Uppercases each ASCII letter of `source` and publishes it as one string.
@aot
local function shout(source: string, capacity: uint32, nullValue: any): any
    local depth: uint32 = 4
    local builder = valuebuilder.newSized(nullValue, depth, capacity)
    local scratch = valuebuilder.newByteScratch(capacity)
    local length = valuebuilder.length(source)
    local index: uint32 = 0
    local zero: uint32 = 0
    while index < length do
        local byte = valuebuilder.byte(source, index)
        if byte >= 97 and byte <= 122 then
            byte = nupp.math.u32.sub(byte, 32)
        end
        valuebuilder.setScratchByte(scratch, index, byte)
        index = nupp.math.u32.add(index, 1)
    end
    valuebuilder.stringScratch(builder, scratch, zero, length)

    return valuebuilder.finish(builder)
end
```

`integerSlice` is the integer-token counterpart of `numberSlice`: short integers
accumulate directly in native code, and longer tokens retain the checked
binary64 conversion fallback.

## Registrar and loading

Every builder in one generated C file shares one digest-named registrar. For
the default shared-library linkage, the generated module resolves its sidecar,
opens that registrar with `package.loadlib`, validates the returned closure
table, and caches that table for the Lua state:

```nupp
local ks_summary_builderRegistrar = "ks_register_c70bc70bcb1fafb2"
-- ...
local open, why = loadlib(path, ks_summary_builderRegistrar)
if not open then error("cannot register AOT builder: " .. tostring(why), 0) end
registered = open()
if type(registered) ~= "table" or type(registered["summary"]) ~= "function" then
    error("malformed AOT builder registration", 0)
end
modules[cacheKey] = registered
```

`nupp aot --emit binding` prints the whole thing, including the walk that finds
the library beside the module. Pure kernels retain their existing FFI path and
have no Lua pointer or GC authority.

With `aotLinkage = "static"` on a component target, the component never opens a
library at runtime. The embedding host links the archive and calls its registrar
with the host-owned `lua_State` before loading the component. The generated
module reads the registered table instead:

```nupp [Generated static binding, private]
local modules = rawget(_G, "__nuppAotBuilderModules")
local registered = modules and modules["ks_register_<component>_<digest>"]
if type(registered) ~= "table" then
    error("AOT builder archive is not registered", 0)
end
```

Lua source cannot call this registrar through `ffi.C`: the registrar needs a
`lua_State *`, which belongs to the embedding host. See
[Static AOT components](../../projects/build.md#static-aot-components) for the build choice
and [Embedding Nupp](../../projects/embedding.md#static-aot-components) for the host handoff.
