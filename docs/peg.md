# Parsing-expression grammars

`nupp.peg` compiles textual parsing-expression grammars into reusable pure-Lua
matchers. The same grammar language works inside `comptime` and at runtime, and
neither path requires LPeg to be installed.

```nupp
const Identifier: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[a-zA-Z_] [a-zA-Z_0-9]* !.")
end

assert(Identifier("item_2") == 7)
assert(Identifier("2_items") == nil)
```

A parsing-expression grammar, or PEG, describes a deterministic top-down parse.
Its choice operator is ordered: `p / q` tries `q` only if `p` fails. This differs
from a regular expression alternation that may choose whichever alternative makes
the complete expression work.

## Compiling at either phase

`nupp.peg.compile(source, options?)` is the only constructor.

A constant call inside `comptime` is parsed and validated by the compiler. The
declared `nupp.peg.Peg<R>` type tells the compiler what result the grammar must
produce. The emitted program receives an already-materialized matcher and does not
carry the textual grammar parser unless some runtime call also needs it.

```nupp
const Word: nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("{ [a-z]+ } !.")
end
```

A normal call compiles a runtime string and returns `nupp.peg.Peg<any>`. Parsed plans
are cached by grammar source and backend, so compiling the same grammar again avoids
the parse and planning work.

```nupp
local function loadMatcher(configuration: string): nupp.peg.Peg<any>
    return nupp.peg.compile(configuration)
end
```

Prefer `comptime` for source-owned constant grammars. Runtime compilation is for
configuration, plugins, user-selected formats, and other genuinely dynamic input.

## Matching and positions

A matcher can be called directly or through `match`:

```nupp
local result = Word("hello")
local same = Word:match("hello")
```

Matching begins at byte position 1 unless `init` is supplied. Positions are 1-based.
A negative `init` counts from the end like Lua string operations. Positions before 1
clamp to 1, and positions after `#subject + 1` fail.

```nupp
local RuntimeWord = nupp.peg.compile("{ [a-z]+ }")
assert(RuntimeWord("one two", 5) == "two")
```

A recognizer with no captures returns the byte position immediately after its match.
It does not return a boolean. Failure returns nil.

```nupp
local Prefix = nupp.peg.compile("'get'")
assert(Prefix("getter") == 4)
assert(Prefix("setter") == nil)
```

Append `!.` to require the end of the subject and therefore a complete match:

```nupp
local Whole = nupp.peg.compile("'get' !.")
assert(Whole("get") == 4)
assert(Whole("getter") == nil)
```

All positions and classes are byte-oriented. The grammar does not decode UTF-8
codepoints. A literal UTF-8 character is matched as its encoded byte sequence, while
`.` consumes one byte rather than one Unicode character.

## Expression syntax

Whitespace between expressions is ignored. A `--` comment outside a quoted literal
or byte class continues to the end of the line.

Precedence runs from tightest to loosest:

1. primary expressions such as literals, classes, captures, and groups;
2. repetition suffixes and action suffixes;
3. predicates;
4. sequence;
5. ordered choice `/`.

Parentheses can make any grouping explicit.

### Literals and any byte

Single-quoted and double-quoted literals match their contents exactly:

```text
'GET'
"Content-Type"
```

The grammar notation does not process backslash escapes. A backslash in a literal is
a literal backslash byte. Use the other quote delimiter when the text contains one
kind of quote:

```text
"it's"
'say "yes"'
```

An empty literal `''` succeeds without consuming input. It is occasionally useful in
a choice, but it must not appear inside `*` or `+` because such a loop could never
advance.

`.` matches any one byte. It fails at the end of the subject.

### Byte classes

Square brackets match one byte from a set. Ranges are inclusive:

```text
[abc]
[a-zA-Z_]
[0-9a-fA-F]
```

`^` immediately after `[` complements the class:

```text
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
| `%nl` | | newline |
| `%p` | `%punct` | ASCII punctuation |
| `%s` | `%space` | ASCII whitespace |
| `%u` | `%upper` | uppercase ASCII letters |
| `%w` | `%alnum` | ASCII letters and digits |
| `%x` | `%xdigit` | hexadecimal digits |

The one-letter uppercase forms `%A`, `%C`, `%D`, `%G`, `%L`, `%P`, `%S`, `%U`,
`%W`, and `%X` match the complement of their lowercase class. Predefined classes can
also appear inside square brackets:

```text
[%a_]
[%w.-]
```

Class contents are literal bytes except for ranges and `%` classes. An empty class
and a descending range such as `[z-a]` are errors.

### Sequence

Adjacent expressions form a sequence and must match in order:

```text
'HTTP/' [0-9] '.' [0-9]
```

Spacing is optional when token boundaries remain clear, but whitespace usually makes
grammars easier to read.

### Ordered choice

`p / q` tries `p` first and uses `q` only when `p` fails:

```text
'GET' / 'POST' / 'PUT'
```

Put a longer literal before its prefix. With `'in' / 'integer'`, the first arm
succeeds after two bytes and the second arm is never considered. Write
`'integer' / 'in'` instead, or add a boundary assertion to each arm.

PEG backtracking is local and deterministic. If a later expression fails, the parser
can return to a still-open choice and try its next arm. User actions are deferred until
the entire match succeeds, so speculative paths do not run callbacks.

### Repetition

Suffix operators repeat the expression immediately to their left:

| Form | Meaning |
| --- | --- |
| `p?` | zero or one |
| `p*` | zero or more |
| `p+` | one or more |
| `p^4` | exactly four |
| `p^+4` | at least four |
| `p^-4` | at most four |

Use parentheses to repeat a sequence:

```text
[0-9]+ ('.' [0-9]+)?
```

Repetition is possessive in PEG fashion. It consumes as much as it can and does not
backtrack to a smaller count merely to make a following expression work. A repeated
expression must consume at least one byte whenever it succeeds. Nullable repetition,
such as `('')*`, is rejected rather than allowed to loop forever.

Explicit repetition counts are limited to 4096.

### Predicates and end of input

`&p` succeeds when `p` would succeed and consumes nothing. `!p` succeeds when `p`
would fail and also consumes nothing.

```text
&[a-z] [a-z]+
!('if' !.) [a-z]+ !.
```

The first expression requires a lowercase next byte before consuming a word. The
second rejects the complete keyword `if` while still accepting identifiers beginning
with those letters, such as `iffy`.

`!.` is the standard end-of-input assertion: it succeeds only when `.` cannot consume
another byte.

### Captures and result types

`{ p }` captures the substring consumed by `p`:

```nupp
const Name: nupp.peg.Peg<string> = comptime do
    return nupp.peg.compile("{ [a-z]+ } !.")
end
```

`{}` captures the current byte position without consuming input:

```nupp
const Start: nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("{} [a-z]+ !.")
end
```

`{| p |}` collects every capture produced by `p` into one array:

```nupp
const Fields: nupp.peg.Peg<{string}> = comptime do
    return nupp.peg.compile(
        "{| { [a-z]+ } (',' { [a-z]+ })* |} !."
    )
end
```

A matcher has one top-level result. A sequence that would return several separate
captures is rejected. Wrap them in `{| ... |}`. Capturing repetition must also be
inside a collection, since the number of results depends on the subject.

Every ordered-choice arm must produce the same capture shape. This keeps the declared
`Peg<R>` result true regardless of which arm matches.

### Actions

`p => name` and `p -> name` match `p`, then contribute the return value of callback
`name` as an action capture. The callback receives the complete substring consumed by
`p`. The two arrows are synonyms.

For a runtime grammar, pass callbacks in `CompileOptions.actions`:

```nupp
local Integer = nupp.peg.compile("[0-9]+ => integer !.", {
    actions = {
        integer = function(text: string): any
            return assert(tonumber(text))
        end,
    },
})
assert(Integer("42") == 42)
```

For a static grammar, declare a factory whose parameter is a closed record containing
exactly the named callbacks:

```nupp
local record Actions
    integer: function(string): integer
end

const IntegerFactory:
    function(Actions): nupp.peg.Peg<integer> = comptime do
    return nupp.peg.compile("[0-9]+ => integer !.")
end

local Integer = IntegerFactory(new Actions {
    integer = function(text: string): integer
        return assert(tonumber(text)) as integer
    end,
})
```

Callbacks run only after the complete match succeeds. Backtracking cannot invoke a
callback from a discarded parse. Every named slot is required, extra slots are
rejected for static factories, and action names are sorted into a stable binding order.

### Rules and recursion

A source beginning with `name <-` is a grammar made of rule definitions. The first
rule is the start rule:

```text
start <- value !.
value <- 'x' / '(' value ')'
```

Refer to a rule as `name` or `<name>`. Angle brackets are useful where adjoining text
would make the boundary unclear.

Rules may recurse after consuming input. Direct and indirect left recursion are
rejected because a top-down PEG cannot enter a rule again at the same position:

```text
-- Invalid: value calls itself before consuming anything.
value <- value ',' item / item
```

Rewrite left-recursive lists as a head followed by repetition:

```text
value <- item (',' item)*
```

Every reference must resolve, rule names must be unique, and expression nesting is
limited to 256 levels.

## Backends

`CompileOptions.backend` accepts `"auto"` or `"vm"`.

`auto` is the default. It recognizes measured grammar shapes and selects shared
specialized matcher templates. Other grammars use the general bytecode VM. Static and
runtime compilation select the same templates, so a runtime-compiled specialization
has the same hot matcher code as its static counterpart after setup.

```nupp
local Fast = nupp.peg.compile("[a-z]+ !.")
```

`vm` skips specialization and always emits or builds a bounded bytecode program:

```nupp
local General = nupp.peg.compile("[a-z]+ !.", {backend = "vm"})
```

Use `vm` for reproducible backend comparisons, cold dynamic grammars, or applications
that prefer a single predictable implementation. This option disables Nupp's matcher
specialization; the host LuaJIT may still compile hot Lua code in its usual way.

Runtime compilation never calls `loadstring` and never allocates native executable
memory. It parses data, selects a shared matcher template or builds PEG bytecode, and
binds callbacks.

## LPeg `re` relationship

The notation intentionally follows the byte-oriented floor of LPeg's `re` syntax, so
many ordinary recognition grammars transfer directly. It is not a complete clone of
every LPeg capture, locale definition, match-time capture, or external-definition
facility. Nupp adds named action slots and a one-result typed capture discipline.

The exact supported surface is the syntax documented on this page. Unsupported
notation fails during `comptime` for a static grammar or during `compile` for a runtime
grammar, with a line and byte-column location.

See [the runnable PEG example](../examples/peg.nupp) for recognition, collections,
recursive rules, typed static actions, runtime grammars, and the VM backend.
