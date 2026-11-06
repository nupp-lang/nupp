---
order: 310
---

# Overloads and overrides

An overload is one operation with several accepted parameter packs. A call
selects the single entry that accepts its arguments, whether those entries come
from a callable intersection, from repeated method bodies, or from repeated
constructors.

```nupp
local record Token
    kind: string
end

local record Ast
    source: string
end

local type Decode = function(string): Ast & function({Token}): Ast

local decode: Decode = nil as any
local fromText: Ast = decode("name")
local fromTokens: Ast = decode({Token(kind = "name")})
return fromText, fromTokens
```

Selection is exact: the call is an error unless exactly one entry accepts it.
Nothing is ranked, and nothing is dispatched at run time. One thing does break
a tie between entries that both accept the call: parameter ownership modes. A
plain or borrowed callback prefers an entry whose slot is `scoped`, and an
owner prefers an entry whose slot `takes` it, so a pair of arms differing only
in mode selects the arm written for that kind of argument rather than
reporting an ambiguity.

## Callable intersections

An intersection containing only function types is an overload contract. It
describes one callable value with several contracts rather than several
implementations:

```nupp
local record Ast
    source: string
end

local type Decode = function(string): Ast & function({string}): Ast

local decode: Decode = nil as any
const parsed: Ast = decode("name")
const rebuilt: Ast = decode({"name"})
```

The checker infers the complete argument pack once, probes every member without
changing ownership or borrow state, and accepts the call only when exactly one
member survives. The winner supplies its whole result pack, ownership modes,
borrowing and FFI output provenance, predicate narrowing, and `noreturn`
contract. Rejected candidates move no affine arguments and establish no
borrows. See [Intersections](intersections.md) for the relation `&` builds and
for the intersections no value can satisfy.

Subtype overlap is the usual way to write a real tie. An integer satisfies both
`integer` and `number`, and Nupp does not guess that the narrower type was
meant:

```nupp:refused
-- reports: NUPP2126
local type Render = function(integer): string & function(number): string
local render: Render = nil as any
return render(1)
```

No surviving member is reported at the call:

```nupp:refused
-- reports: NUPP2125
local type Parse = function(string): string & function(boolean): string
local parse: Parse = nil as any
return parse(1)
```

A correlated argument-pack union must be accepted by one member across all of
its alternatives. See [Type packs](packs.md#correlated-alternatives) for how
such a pack is formed.

## Separate method bodies

Repeated names create overloads on their own, so there is no `@overload`
annotation. Write each implementation under the same name:

```nupp
local record Token
    kind: string
end

local record Ast
    source: string
end

local function parseText(text: string): Ast
    return Ast(source = text)
end

local function parseTokens(tokens: {Token}): Ast
    return Ast(source = tokens[1].kind)
end

local record Decoder
    function decode(self, text: string): Ast
        return parseText(text)
    end

    function decode(self, tokens: {Token}): Ast
        return parseTokens(tokens)
    end
end

local decoder = Decoder()
local textAst = decoder:decode("name")
local tokenAst = decoder:decode({Token(kind = "name")})
return textAst, tokenAst
```

The visible type of `decode` is an intersection of its callable signatures. The
compiler also retains two method entries: each entry has its own body, effects,
source definition, and stable hidden runtime slot. Once the checker selects an
entry, code generation calls that slot directly with ordinary Lua colon
semantics. The receiver is evaluated once and no dispatcher runs.

### Method groups are not field values

There is no runtime value corresponding to the source name `decoder.decode`:

```nupp:refused
-- reports: NUPP2126
local record Decoder
    function decode(self, text: string): string
        return text
    end

    function decode(self, value: integer): string
        return tostring(value)
    end
end

local decoder = Decoder()
local held = decoder.decode
return held
```

Write an adapter when a callback needs one selected operation:

```nupp
local record Decoder
    function decode(self, text: string): string
        return text
    end

    function decode(self, value: integer): string
        return tostring(value)
    end
end

local decoder = Decoder()
local fromText: function(string): string = function(text: string): string
    return decoder:decode(text)
end
return fromText("ready")
```

The adapter is explicit about which parameter pack it exposes and remains an
ordinary first-class Lua function.

### Ambiguity from `any`

An `any` argument may leave several entries possible:

```nupp:refused
-- reports: NUPP2126
local record Decoder
    function decode(self, text: string): string
        return text
    end

    function decode(self, value: integer): string
        return tostring(value)
    end
end

local decoder = Decoder()
local input: any = "ready"
return decoder:decode(input)
```

An explicit cast selects the intended entry:

```nupp
local record Decoder
    function decode(self, text: string): string
        return text
    end

    function decode(self, value: integer): string
        return tostring(value)
    end
end

local decoder = Decoder()
local input: any = "ready"
return decoder:decode(input as string)
```

### Parameter packs select the entry

Two bodies cannot differ only by return type:

```nupp:refused
-- reports: NUPP2118
local record Bad
    function get(self, value: string): string
        return value
    end

    function get(self, value: string): integer
        return 1
    end
end
```

The call has to choose a body before it can obtain a result, so an expected
result type cannot resolve this ambiguity. Parameter ownership modes, generic
bounds, and pack tails participate in entry identity; return packs do not.

## Bodyless interface contracts

An [interface](interfaces.md) with no implementation writes the method as a
callable intersection field. Matching record bodies use the same
signature-derived slots:

```nupp
local interface DecoderContract
    decode: function(self, string): string & function(self, integer): string
end

local record Decoder is DecoderContract
    function decode(self, text: string): string
        return "text:" .. text
    end

    function decode(self, value: integer): string
        return "number:" .. tostring(value)
    end
end

local decoder: DecoderContract = Decoder()
return decoder:decode("ready"), decoder:decode(42)
```

This is implementation, not replacement: the interface supplied no body, so
these methods do not use `@override`. Every contract entry needs a compatible
record body:

```nupp:refused
-- reports: NUPP2118
local interface DecoderContract
    decode: function(self, string): string & function(self, integer): string
end

local record Incomplete is DecoderContract
    function decode(self, text: string): string
        return text
    end
end
```

A child interface method body can mark an inherited method slot with
`@override` whether or not that slot had a default. The annotation matches
one parameter pack, and the replacement still has to be
type-compatible with that inherited entry.

## Default implementations and `@override`

An interface may instead provide bodies, which a record inherits unless it
replaces them. See [Interfaces](interfaces.md#default-implementations) for
defaults on a method that is not overloaded.

### Replacing one entry

`@override` matches the exact parameter pack, so one overload may be replaced
while the other defaults stay inherited:

```nupp
local interface Decoder
    function decode(self, text: string): string
        return "default:" .. text
    end

    function decode(self, value: integer): string
        return "number:" .. tostring(value)
    end
end

local record LoudDecoder is Decoder
    @override
    function decode(self, text: string): string
        return "loud:" .. text
    end
end

local decoder: Decoder = LoudDecoder()
return decoder:decode("ready"), decoder:decode(42)
```

Omitting `@override` from the string body is reported, and putting it on a
parameter pack with no inherited body is reported as well:

```nupp:refused
-- reports: NUPP2118
local interface Decoder
    function decode(self, text: string): string
        return text
    end

    function decode(self, value: integer): string
        return tostring(value)
    end
end

local record Wrong is Decoder
    @override
    function decode(self, flag: boolean): string
        return tostring(flag)
    end
end
```

### Adding an overload beside a default

A record may replace one default and add an entry the interface never declared.
Only the replacement uses `@override`:

```nupp
local interface Formatter
    function format(self, text: string): string
        return text
    end
end

local record DetailedFormatter is Formatter
    @override
    function format(self, text: string): string
        return "text:" .. text
    end

    function format(self, value: integer): string
        return "integer:" .. tostring(value)
    end
end

local formatter = DetailedFormatter()
return formatter:format("ready"), formatter:format(42)
```

### Defaults from several interfaces

Two interfaces can contribute different default entries under the same source
name. Their distinct parameter packs form one inherited overload group:

```nupp
local interface TextDecoder
    function decode(self, text: string): string
        return "text:" .. text
    end
end

local interface NumberDecoder
    function decode(self, value: integer): string
        return "number:" .. tostring(value)
    end
end

local record Decoder is TextDecoder, NumberDecoder
end

local decoder = Decoder()
return decoder:decode("ready"), decoder:decode(42)
```

Two interfaces providing the same parameter pack provide competing bodies for
one entry. The record must write a compatible body to resolve the conflict.

## Generic method overloads

[Generic](generics.md) declaration parameters remain part of each entry and
specialize at the call site without changing its runtime slot:

```nupp
local record Codec<T>
    function encode(self, value: T): string
        return "one:" .. tostring(value)
    end

    function encode(self, values: {T}): string
        return "many:" .. tostring(values[1])
    end
end

local codec = Codec<integer>()
return codec:encode(4), codec:encode({5})
```

The compiler selects using the specialized signatures but invokes the bodies'
stable declaration slots. Calls through a generic interface use the same rule.

## Constructor overloads

Constructors already have separate bodies, so repeating `constructor` declares
the overload group:

```nupp
local record Value
    text: string

    constructor(self, value: integer)
        self.text = tostring(value)
    end

    constructor(self, value: string)
        self.text = value
    end
end

local fromNumber = Value(42)
local fromText = Value("ready")
return fromNumber.text, fromText.text
```

`Value(...)` applies the same exact-one rule and directly invokes the
selected constructor body. Duplicate constructor parameter packs are reported,
and declaring any constructor closes named-field construction for that
record. See [Records and
structs](records-and-structs.md#constructors-and-result-policies) for what a constructor
may promise.

The selected entry supplies its whole result policy as well as its body. One
parameter pack may return `File`, while another returns `affine(File,
File.destroy)`. Results never take part in selection: the arguments choose an
entry first, and that entry's result becomes the type of `File(...)`.

## Facades for untyped callers

The hidden method slots are compiler ABI, not source-level Lua member names.
Untyped Lua therefore cannot call `decoder:decode(value)` on an overloaded
record. Export an ordinary function that makes an explicit runtime decision
where a dynamic boundary needs one:

```nupp
local record Token
    kind: string
end

local record Ast
    source: string
end

local record Decoder
    function decode(self, text: string): Ast
        return Ast(source = text)
    end

    function decode(self, tokens: {Token}): Ast
        return Ast(source = tokens[1].kind)
    end
end

local decoder = Decoder()

local function decodeDynamic(input: any): Ast
    if type(input) == "string" then
        return decoder:decode(input as string)
    end
    return decoder:decode(input as {Token})
end

return decodeDynamic("ready")
```

That dispatcher exists because the program asked for a dynamic facade. Typed
method calls do not pay for it. See [Escape hatches](index.md#escape-hatches)
for the rest of what crosses that boundary.
