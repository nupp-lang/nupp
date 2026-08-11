# Overloads and overrides

An overload is one operation with several accepted parameter packs. Nupp uses
the same exact-one selection rule for callable intersections, repeated method
bodies, and constructors. Method overloads keep separate bodies and compile to
direct calls; they are not runtime dispatch functions hidden behind one name.

`@override` answers a different question. It says that one method body replaces
an inherited interface default with the same parameter pack. Repeated names
create overloads automatically, so there is no `@overload` annotation.

## Callable intersections

An intersection containing only function types is an overload contract:

```nupp
local record Token
    kind: string
end

local record Ast
    source: string
end

local type Decode = function(string): Ast
    & function({Token}): Ast

local decode: Decode = nil as any
local fromText: Ast = decode("name")
local fromTokens: Ast = decode({new Token(kind = "name")})
return fromText, fromTokens
```

The checker infers the complete argument pack once, probes every member without
changing ownership or borrow state, and accepts the call only when exactly one
member survives. Declaration order does not break a tie and there is no
best-match ranking.

A callable intersection describes one callable value with several contracts.
It does not itself create several implementations. Repeated method declarations
are what give several bodies to one method name.

## Separate method bodies

Write each method implementation under the same name:

```nupp
local record Token
    kind: string
end

local record Ast
    source: string
end

local function parseText(text: string): Ast
    return new Ast(source = text)
end

local function parseTokens(tokens: {Token}): Ast
    return new Ast(source = tokens[1].kind)
end

local record Decoder
    function decode(self, text: string): Ast
        return parseText(text)
    end

    function decode(self, tokens: {Token}): Ast
        return parseTokens(tokens)
    end
end

local decoder = new Decoder()
local textAst = decoder:decode("name")
local tokenAst = decoder:decode({new Token(kind = "name")})
return textAst, tokenAst
```

The visible type of `decode` is an intersection of its callable signatures.
The compiler also retains two method entries: each entry has its own body,
effects, source definition, and stable hidden runtime slot. Once the checker
selects an entry, code generation calls that slot directly with ordinary Lua
colon semantics. The receiver is evaluated once and no dispatcher runs.

### A method group is not one field value

There is no runtime value corresponding to the source name `decoder.decode`:

```nupp
-- reports: NUPP2126
local record Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end

local decoder = new Decoder()
local held = decoder.decode
return held
```

Write an adapter when a callback needs one selected operation:

```nupp
local record Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end

local decoder = new Decoder()
local fromText: function(string): string = function(text: string): string
    return decoder:decode(text)
end
return fromText("ready")
```

The adapter is explicit about which parameter pack it exposes and remains an
ordinary first-class Lua function.

### Ambiguous and rejected calls

An `any` argument may leave several entries possible:

```nupp
-- reports: NUPP2126
local record Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end

local decoder = new Decoder()
local input: any = "ready"
return decoder:decode(input)
```

An explicit cast selects the intended entry:

```nupp
local record Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end

local decoder = new Decoder()
local input: any = "ready"
return decoder:decode(input as string)
```

Subtype overlap can be ambiguous too. An integer satisfies both `integer` and
`number`, and Nupp does not guess that the narrower spelling was preferred:

```nupp
-- reports: NUPP2126
local type Render = function(integer): string
    & function(number): string
local render: Render = nil as any
return render(1)
```

No surviving member is **NUPP2125**:

```nupp
-- reports: NUPP2125
local type Parse = function(string): string
    & function(boolean): string
local parse: Parse = nil as any
return parse(1)
```

### Parameter packs, not results, select

Two bodies cannot differ only by return type:

```nupp
-- reports: NUPP2118
local record Bad
    function get(self, value: string): string return value end
    function get(self, value: string): integer return 1 end
end
```

The call has to choose a body before it can obtain a result, so an expected
result type cannot resolve this ambiguity. Parameter ownership modes, generic
bounds, and pack tails participate in entry identity; return packs do not.

## Bodyless interface contracts

An interface with no implementation writes the method as a callable
intersection field. Matching record bodies use the same signature-derived
slots:

```nupp
local interface DecoderContract
    decode: function(self, string): string
        & function(self, integer): string
end

local record Decoder is DecoderContract
    function decode(self, text: string): string return "text:" .. text end
    function decode(self, value: integer): string return "number:" .. tostring(value) end
end

local decoder: DecoderContract = new Decoder()
return decoder:decode("ready"), decoder:decode(42)
```

This is implementation, not replacement: the interface supplied no body, so
these methods do not use `@override`. Every contract entry needs a compatible
record body:

```nupp
-- reports: NUPP2118
local interface DecoderContract
    decode: function(self, string): string
        & function(self, integer): string
end

local record Incomplete is DecoderContract
    function decode(self, text: string): string return text end
end
```

## Default implementations and `@override`

An interface may instead provide bodies. A record inherits every default entry
it does not replace:

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

local decoder: Decoder = new LoudDecoder()
return decoder:decode("ready"), decoder:decode(42)
```

`@override` matches the exact parameter pack. Here it replaces only the string
entry; the integer default remains inherited. Omitting `@override` from the
string body is **NUPP2118**, because replacing inherited behavior must be
explicit. Putting it on a parameter pack with no inherited body is also
**NUPP2118**:

```nupp
-- reports: NUPP2118
local interface Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end

local record Wrong is Decoder
    @override
    function decode(self, flag: boolean): string return tostring(flag) end
end
```

A record may replace one default and add another overload. Only the replacement
uses `@override`:

```nupp
local interface Formatter
    function format(self, text: string): string return text end
end

local record DetailedFormatter is Formatter
    @override
    function format(self, text: string): string return "text:" .. text end

    function format(self, value: integer): string return "integer:" .. tostring(value) end
end

local formatter = new DetailedFormatter()
return formatter:format("ready"), formatter:format(42)
```

Two interfaces can contribute different default entries under the same source
name. Their distinct parameter packs form one inherited overload group:

```nupp
local interface TextDecoder
    function decode(self, text: string): string return "text:" .. text end
end

local interface NumberDecoder
    function decode(self, value: integer): string return "number:" .. tostring(value) end
end

local record Decoder is TextDecoder, NumberDecoder
end

local decoder = new Decoder()
return decoder:decode("ready"), decoder:decode(42)
```

If two interfaces provide the same parameter pack, they provide competing
bodies for one entry. The record must write a compatible body to resolve the
conflict.

## Generic method overloads

Generic declaration parameters remain part of each entry and specialize at the
call site without changing its runtime slot:

```nupp
local record Codec<T>
    function encode(self, value: T): string
        return "one:" .. tostring(value)
    end

    function encode(self, values: {T}): string
        return "many:" .. tostring(values[1])
    end
end

local codec: Codec<integer> = new Codec()
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

local fromNumber = new Value(42)
local fromText = new Value("ready")
return fromNumber.text, fromText.text
```

`new Value(...)` applies the same exact-one selection rule and directly invokes
the selected constructor body. Duplicate constructor parameter packs are
**NUPP2208**.

## Untyped callers need an explicit facade

The hidden method slots are compiler ABI, not source-level Lua member names.
Untyped Lua therefore cannot call `decoder:decode(value)` on an overloaded
record. Export an ordinary function that performs an explicit runtime decision
when a dynamic boundary needs one:

```nupp
local record Token
    kind: string
end

local record Ast
    source: string
end

local record Decoder
    function decode(self, text: string): Ast return new Ast(source = text) end
    function decode(self, tokens: {Token}): Ast return new Ast(source = tokens[1].kind) end
end

local decoder = new Decoder()

local function decodeDynamic(input: any): Ast
    if type(input) == "string" then
        return decoder:decode(input as string)
    end
    return decoder:decode(input as {Token})
end

return decodeDynamic("ready")
```

That dispatcher exists because the program asked for a dynamic facade. Typed
method calls do not pay for it.

## Diagnostics

| Code | Meaning here |
| --- | --- |
| **NUPP2125** | No callable-intersection member accepts the argument pack. |
| **NUPP2126** | Several members accept it, or an overloaded method was read as one field value. |
| **NUPP2118** | A method parameter pack is duplicated, an interface entry is missing or incompatible, or `@override` does not match exactly one inherited default. |
| **NUPP2208** | Constructor overloads duplicate a parameter pack or violate constructor integrity. |

For the underlying intersection relation, including capability composition and
provable emptiness, see [Intersection types](intersections.md). For general
interface inheritance and runtime defaults, see [Interfaces](interfaces.md).
