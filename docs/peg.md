# Parsing-expression grammars

`nupp.peg` compiles textual parsing-expression grammars into reusable typed
matchers. The same grammar language works inside `comptime` and at runtime.
Nupp ships native LPeg and uses it for general matching while retaining a few
faster specialized Lua kernels.

```nupp:playground
const Identifier = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end

assert(Identifier("item_2") == 7)
assert(Identifier("2_items") == nil)
```

A parsing-expression grammar, or PEG, describes a deterministic top-down parse.
Its choice operator is ordered: `p / q` tries `q` only if `p` fails. This
differs from a regular expression alternation that may choose whichever
alternative makes the complete expression work.

## Compiling at either phase

`nupp.peg.compile(source, options?)` is the only constructor.

A constant call inside `comptime` is parsed and validated by the compiler. The
compiler derives `nupp.peg.Peg<R...>` from the validated capture shape, so
recognizers, substring and position captures, and collections do not need result
annotations. The emitted program receives an already-materialized matcher and
does not carry the textual grammar parser unless some runtime call also needs
it.

```nupp
const Word = comptime do
    return nupp.peg.compile("{ [a-z]+ } !.")
end
```

A normal call with literal grammar text gets the same inferred `Peg<R...>` type.
It still compiles at runtime; parsed plans are cached by grammar source and
backend, so compiling the same grammar again avoids parsing, lowering, and
code-generation work. A genuinely dynamic `string` returns `Peg<...any>` because
its capture shape is not yet known.

```nupp
local function loadMatcher(configuration: string): nupp.peg.Peg<...any>
    return nupp.peg.compile(configuration)
end
```

Prefer `comptime` for source-owned constant grammars. Runtime compilation is for
configuration, plugins, user-selected formats, and other genuinely dynamic
input.

Every `Peg<R...>` satisfies `nupp.peg.Matcher<R...>`. A generic adapter can
forward the complete result pack without collecting it into another value:

```nupp
local function match<R...>(matcher: nupp.peg.Matcher<R...>, subject: string): ((R...) | (nil))
    return matcher:match(subject)
end

local Word = nupp.peg.compile("{ [a-z]+ }")
local word: string? = match(Word, "hello")
```

## Matching and positions

A matcher can be called directly or through `match`:

```nupp
local result = Word("hello")
local same = Word:match("hello")
```

Matching begins at byte position 1 unless `init` is supplied. Positions are
1-based. A negative `init` counts from the end like Lua string operations.
Positions before 1 clamp to 1, and positions after `#subject + 1` fail.

```nupp
local RuntimeWord = nupp.peg.compile("{ [a-z]+ }")
assert(RuntimeWord("one two", 5) == "two")
```

A recognizer with no captures returns the byte position immediately after its
match. It does not return a boolean. Failure returns nil.

```nupp
local Prefix = nupp.peg.compile("'get'")
assert(Prefix("getter") == 4)
assert(Prefix("setter") == nil)
```

Use `find` when the grammar may begin after the starting position. It returns
the first byte, the exclusive next byte, and every grammar result without
constructing a match record.

```nupp
local Word = nupp.peg.compile("{ [a-z]+ }")
local first, nextPosition, value = Word:find("123 hello")
assert(first == 5 and nextPosition == 10 and value == "hello")
```

For `Peg<R...>`, success has the pack `(integer, integer, R...)`; failure has
`(nil, nil)`. The byte range is half-open, `[first, nextPosition)`, so an empty
match has equal positions. On failure the positions are nil. Test `first` for
success because a grammar action may successfully return nil or false. A
recognizer's third result is the same next-byte position it returns from
`match`.

Use `isMatch` when only existence matters. It performs the same search and
returns only a boolean:

```nupp
local Digits = nupp.peg.compile("[0-9]+")
assert(Digits:isMatch("room 42"))
assert(not Digits:isMatch("room"))
assert(not Digits:isMatch("42 rooms", 3))
```

The default `init` is 1 and its normalization is the same as for `match`. The
position after the last byte is included, allowing an empty or end assertion to
match there. Use `match` when the exact starting position is already known.

## Repeated matching

`forEachMatch` visits non-overlapping matches without constructing match records
or an iterator closure. Its callback receives `first, nextPosition, R...`, the
same values as `find`, and the return value is the number of visits:

```nupp
local Word = nupp.peg.compile("{ [a-z]+ }")
local words: {string} = {}
local count = Word:forEachMatch("one, two, three", function(first: integer, nextPosition: integer, value: string)
    assert(first < nextPosition)
    words[#words + 1] = value
end)

assert(count == 3)
assert(words[2] == "two")
```

The next search begins at the exclusive end of a consuming match. An empty match
instead advances one byte, so an empty grammar cannot repeatedly report the same
position. The boundary at `#subject + 1` remains eligible and is visited at most
once. For example, `''` visits positions 1, 2, and 3 in a two-byte subject.

The optional `init` controls the first position considered and follows `find`'s
normalization rules. Text before it is not visited. The visitor's return value
is ignored; an error is the way to abort a traversal.

## Replacement

`replace` replaces the first match, while `replaceAll` replaces every
non-overlapping match. A string replacement is inserted literally:

```nupp
local Digits = nupp.peg.compile("[0-9]+")
assert(Digits:replace("room 42, floor 3", "#") == "room #, floor 3")
assert(Digits:replaceAll("room 42, floor 3", "#") == "room #, floor #")
```

Replacement strings do not interpret `$`, `%`, or capture references. Use a
typed callback when replacement text depends on the match. It receives the raw
positions followed by every grammar result and must return a string:

```nupp
local Word = nupp.peg.compile("{ [a-z]+ }")
local output = Word:replaceAll("one, two", function(first: integer, nextPosition: integer, value: string): string
    return "[" .. tostring(first) .. ":" .. tostring(nextPosition) .. " " .. value:upper() .. "]"
end)

assert(output == "[1:4 ONE], [6:9 TWO]")
```

Neither operation builds match records. A callback can use a substring capture
as above, use another typed grammar result, or slice the original subject with
the reported half-open range. When no match exists, the original string is
returned. The optional `init` leaves the prefix before it unchanged.

Empty matches insert without removing a byte. `replaceAll` then preserves one
byte while advancing to the next search position; an empty grammar therefore
turns `"ab"` into `"-a-b-"` when replacing with `"-"`. This is the same progress
rule used by `forEachMatch`.

Append `!.` to require the end of the subject and therefore a complete match:

```nupp
local Whole = nupp.peg.compile("'get' !.")
assert(Whole("get") == 4)
assert(Whole("getter") == nil)
```

All positions and classes are byte-oriented. The grammar does not decode UTF-8
codepoints. A literal UTF-8 character is matched as its encoded byte sequence,
while `.` consumes one byte rather than one Unicode character.

## Expression syntax

Whitespace between expressions is ignored. A `--` comment outside a quoted
literal or byte class continues to the end of the line.

Precedence runs from tightest to loosest:

1. primary expressions such as literals, classes, captures, and groups;
2. repetition and capture-transformation suffixes;
3. predicates;
4. sequence;
5. ordered choice `/`.

Parentheses can make any grouping explicit.

### Literals and any byte

Single-quoted and double-quoted literals match their contents exactly:

```npeg
'GET'
"Content-Type"
```

The grammar notation does not process backslash escapes. A backslash in a
literal is a literal backslash byte. Use the other quote delimiter when the text
contains one kind of quote:

```npeg
"it's"
'say "yes"'
```

An empty literal `''` succeeds without consuming input. It is occasionally
useful in a choice, but it must not appear inside `*` or `+` because such a loop
could never advance.

`.` matches any one byte. It fails at the end of the subject.

### Byte classes

Square brackets match one byte from a set. Ranges are inclusive:

```npeg
[abc]
[a-zA-Z_]
[0-9a-fA-F]
```

`^` immediately after `[` complements the class:

```npeg
[^0-9]
```

The predefined ASCII classes are:

| Short | Long | Bytes |
| --- | --- | --- |
| `%a` | `%alpha` | ASCII letters |
| `%c` | `%cntrl` | control bytes and DEL |
| `%d` | `%digit` | decimal digits |
| `%g` | `%graph` | printable non-space ASCII bytes |
| `%l` | `%lower` | lowercase ASCII letters |
| `%nl` |  | newline |
| `%p` | `%punct` | ASCII punctuation |
| `%s` | `%space` | ASCII whitespace |
| `%u` | `%upper` | uppercase ASCII letters |
| `%w` | `%alnum` | ASCII letters and digits |
| `%x` | `%xdigit` | hexadecimal digits |

The one-letter uppercase forms `%A`, `%C`, `%D`, `%G`, `%L`, `%P`, `%S`, `%U`,
`%W`, and `%X` match the complement of their lowercase class. Predefined classes
can also appear inside square brackets:

```npeg
[%a_]
[%w.-]
```

Class contents are literal bytes except for ranges and `%` classes. An empty
class and a descending range such as `[z-a]` are errors.

### Sequence

Adjacent expressions form a sequence and must match in order:

```npeg
'HTTP/' [0-9] '.' [0-9]
```

Spacing is optional when token boundaries remain clear, but whitespace usually
makes grammars easier to read.

### Ordered choice

`p / q` tries `p` first and uses `q` only when `p` fails:

```npeg
'GET' / 'POST' / 'PUT'
```

Put a longer literal before its prefix. With `'in' / 'integer'`, the first arm
succeeds after two bytes and the second arm is never considered. Write
`'integer' / 'in'` instead, or add a boundary assertion to each arm.

PEG backtracking is local and deterministic. If a later expression fails, the
parser can return to a still-open choice and try its next arm. Ordinary `->`
transformations are deferred until the entire match succeeds, so speculative
paths do not run them. Match-time `=>` definitions are intentionally immediate,
as in LPeg.

### Repetition

Suffix operators repeat the expression immediately to their left:

| Form | Meaning |
| --- | --- |
| p? | zero or one |
| p* | zero or more |
| p+ | one or more |
| p^4 | exactly four |
| p^+4 | at least four |
| p^-4 | at most four |

Use parentheses to repeat a sequence:

```npeg
[0-9]+ ('.' [0-9]+)?
```

Repetition is possessive in PEG fashion. It consumes as much as it can and does
not backtrack to a smaller count merely to make a following expression work. A
repeated expression must consume at least one byte whenever it succeeds.
Nullable repetition, such as `('')*`, is rejected rather than allowed to loop
forever.

Explicit repetition counts are limited to 4096.

### Predicates and end of input

`&p` succeeds when `p` would succeed and consumes nothing. `!p` succeeds when
`p` would fail and also consumes nothing.

```npeg
&[a-z] [a-z]+
!('if' !.) [a-z]+ !.
```

The first expression requires a lowercase next byte before consuming a word. The
second rejects the complete keyword `if` while still accepting identifiers
beginning with those letters, such as `iffy`.

`!.` is the standard end-of-input assertion: it succeeds only when `.` cannot
consume another byte.

### Captures and result types

`{ p }` captures the substring consumed by `p`:

```nupp
const Name = comptime do
    return nupp.peg.compile("{ [a-z]+ } !.")
end
```

`{}` captures the current byte position without consuming input:

```nupp
const Start = comptime do
    return nupp.peg.compile("{} [a-z]+ !.")
end
```

`{| p |}` collects every capture produced by `p` into one table:

```nupp
const Fields = comptime do
    return nupp.peg.compile("{| { [a-z]+ } (',' { [a-z]+ })* |} !.")
end
```

Adjacent captures are adjacent native Lua results. For example, the following
grammar is inferred as `Peg<(string, integer)>` and returns two values without a
tuple or table allocation:

```nupp
local Field = nupp.peg.compile("{ [a-z]+ } ':' {}")
local name, nextPosition = Field("size:")
```

The parentheses in `Peg<(string, integer)>` delimit one explicit type-pack
argument; they do not construct a tuple type or a runtime tuple value. Usually
the compiler infers that pack, so the annotation is only needed at an API
boundary.

`{| ... |}` and `p -> {}` remain explicit table captures. Use one when the
grammar semantically produces a collection, especially around capture-producing
repetition; the table allocation then comes from the grammar rather than from
the matcher API.

Every ordered-choice arm must produce the same capture shape. This keeps the
inferred `Peg<R...>` result pack true regardless of which arm matches.

### Groups, substitution, and back captures

`{: name: p :}` groups the captures made by `p` under `name`. Inside a table
capture, that group becomes a named field. Leave out `name:` to make an
anonymous group. `=name` matches the exact string stored by an earlier named
group:

```nupp
local Pair = nupp.peg.compile("{| {: key: { [a-z]+ } :} '=' {: value: { [0-9]+ } :} |} !.")
local fields = assert(Pair("size=42"))
assert(fields.key == "size" and fields.value == "42")

local Repeated = nupp.peg.compile("{: word: { [a-z]+ } :} ':' =word !.")
assert(Repeated("same:same") == "same")
assert(Repeated("same:other") == nil)
```

`{~ p ~}` is LPeg's substitution capture. It returns the complete substring
consumed by `p`, replacing each captured range inside it by that capture's
value:

```nupp
local Normalize = nupp.peg.compile("{~ ({ [0-9]+ } -> '[%0]' / .)* ~} !.")
assert(Normalize("a12b") == "a[12]b")
```

### Transformations and definitions

The suffix `p -> {}` collects `p`'s captures into a table. `p -> n` selects
capture number `n`; zero suppresses all captures. `p -> 'format'` uses LPeg's
capture format, where `%0` is the whole text consumed by `p`, `%1` through `%9`
select captures, and `%%` writes a percent sign.

`p -> name` applies the value named by `name`. A function receives `p`'s
captures, or the complete matched substring when `p` has no explicit capture.
LPeg-compatible string, number, and table transformations are accepted too.
Ordinary function transformations are deferred until the whole match wins.

For a runtime grammar, pass named values in `CompileOptions.definitions`:

```nupp
local Integer = nupp.peg.compile("[0-9]+ -> integer !.", {definitions = {integer = function(text: string): integer
    return assert(tonumber(text)) as integer
end,},})
assert(Integer("42") == 42)
```

Here `Integer` is inferred as `nupp.peg.Peg<integer>` from the transformation's
declared return pack. A transformation may return several values; they are
spliced into the grammar's surrounding result pack. If either the grammar or
definitions table is dynamic, annotate or cast the result where the application
has the missing knowledge.

For a static grammar, declare a factory whose parameter is a closed record
containing exactly the named callbacks:

```nupp
local record Definitions
    integer: function(string): integer
end

const IntegerFactory: function(Definitions): nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[0-9]+ -> integer !.")
end

local Integer = IntegerFactory(new Definitions(integer = function(text: string): integer
    return assert(tonumber(text)) as integer
end))
```

Every named slot is required and extra slots are rejected for static factories.
`CompileOptions.actions` remains a deprecated alias for older Nupp grammars.

The other LPeg `re` definition operators retain their distinct meanings:

- `%name` uses a supplied value as a pattern. Strings match literally,
  non-negative integers match that many bytes, and booleans always succeed or
  fail.
- `p => name` invokes a match-time function with the subject, current byte
  position, and captures. It returns a new position followed by replacement
  captures, or nil to fail. Because it participates in parsing, backtracking may
  invoke it speculatively.
- `p >> name` combines the previous capture with `p`'s capture.
- `p ~> name` folds `p`'s captures from left to right.

### Rules and recursion

A source beginning with `name <-` is a grammar made of rule definitions. The
first rule is the start rule:

```npeg
start <- value !.
value <- 'x' / '(' value ')'
```

Refer to a rule as `name` or `<name>`. Angle brackets are useful where adjoining
text would make the boundary unclear.

Rules may recurse after consuming input. Direct and indirect left recursion are
rejected because a top-down PEG cannot enter a rule again at the same position:

```npeg
-- Invalid: value calls itself before consuming anything.
value <- value ',' item / item
```

Rewrite left-recursive lists as a head followed by repetition:

```npeg
value <- item (',' item)*
```

Every reference must resolve, rule names must be unique, and expression nesting
is limited to 256 levels.

## Backends

`CompileOptions.backend` accepts `"auto"` or `"lpeg"`.

`auto` is the default. Every static grammar becomes a validated canonical PEG
graph. Nupp recognizes a few common shapes—fixed-width matches, repeated bytes,
and packed whole-input scans—and emits straight-line Lua for them. All other
graphs lower directly to native LPeg patterns. There is no Nupp PEG bytecode or
general-purpose interpreter.

```nupp
local Fast = nupp.peg.compile("[a-z]+ !.")
```

`lpeg` disables Nupp's straight-line specializations and always lowers the graph
to native LPeg. It is useful for backend comparisons:

```nupp
local General = nupp.peg.compile("[a-z]+ !.", {backend = "lpeg"})
```

Runtime textual grammars are compiled by LPeg's `re` module and cached by source.
They do not invoke `loadstring`. The `auto` backend invokes `loadstring` only
when a static graph selects a Nupp specialization; LPeg owns every general match.

This split is possible because Nupp owns the static representation. LPeg pattern
userdata does not expose a public, traversable AST from which the compiler could
recover capture types or optimization facts. Nupp therefore parses static
`nupp.peg` text into its canonical typed graph, derives the `R...` result pack
there, and then either emits a selected kernel or constructs the equivalent LPeg
pattern. The graph is a type-system and optimization layer, not another parsing
machine.

Direct `require("lpeg")` returns the native LPeg 1.1 module. Nupp's declaration
and operator checking track capture packs through ordinary LPeg composition, but
the runtime object remains LPeg's pattern userdata. `require("re")` returns the
bundled official Lua frontend over that module.

Repeated byte or class plans also emit a direct byte-scanning `forEachMatch`
loop, so traversal does not re-enter LPeg for every match. Typed replacement
callbacks retain the general search loop for plans without a direct traversal.

## LPeg `re` relationship

The expression syntax is LPeg 1.1 `re` syntax: the same operators have the same
parsing and capture meanings, and the test suite runs the official `re` module
as a differential oracle. Nupp gives those open-ended Lua results a static
`R...` pack and also exposes `find`, `isMatch`, repeated matching, and
replacement directly on the compiled matcher.

A bad expression fails during `comptime` for a static grammar or during
`compile` for a runtime grammar, with a line and byte-column location.
