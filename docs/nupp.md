`nupp` is where everything the compiler provides is spelled. Two different
things live under that one name, and telling them apart is the whole of what
this page is for.

## The `nupp` global

`nupp` is a table the prelude declares, so it is in scope everywhere without a
`require`. Nothing loads it and nothing can shadow it by accident — a binding
called `nupp` shadows it deliberately, the way a binding called `string` would.

It holds the parts of the language that are values rather than syntax:

```
 Name             What it is
 ───────────────  ────────────────────────────────────────────────
 nupp.regex       Compiled Rust regular expressions
 nupp.dispose     Consume an owner and run its cleanup list
 nupp.borrow      Take an explicit lexical borrow
 nupp.intoRaw     Abandon tracking, in unsafe
 nupp.fromRaw     Assert fresh ownership of a raw value, in unsafe
 nupp.borrowFrom  Assert raw provenance from a named source, in unsafe
 nupp.pin         Bind a managed pointer to its Lua anchor
```

The six ownership entries are intrinsics: the compiler implements them, so they
type nothing like ordinary functions and are not values you can pass around.
Each is also spelled bare — `dispose(handle)` is `nupp.dispose(handle)` — and
the two produce the same diagnostics and the same generated Lua. See
[ownership](ownership.md#the-intrinsics-are-also-spelled-nupp) for which
spelling to reach for.

## The `nupp` modules

`nupp` is also the prefix of the library modules below, which are ordinary
modules reached with `require`. They are not fields of the global above:
`nupp.zone` names a module, while `nupp.dispose` names an intrinsic, and only
the `require` tells you which kind of name you are looking at.

```nupp
local zone = require("nupp.zone")
```

There is no module to require by the bare name `nupp` — nothing sits above them
to hold them together, because they have nothing in common beyond being shipped
with the compiler. They are typed Nupp rather than a description of someone
else's C, and the source that goes into the binary is the source this reference
is generated from, so there is no second copy to drift.
