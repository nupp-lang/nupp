# `nupp.regex`

`nupp.regex` provides compiled Rust regular expressions over Lua byte strings.
It is available through the global `nupp` namespace; no `require` is needed.

Patterns use the Rust [`regex` crate syntax](https://docs.rs/regex/latest/regex/#syntax).
Compilation builds the automaton once, and every method on the returned
expression reuses it. Inline flags such as `(?i)` and `(?m)` configure a
pattern without a separate options table.

```nupp
local trailingDigits = nupp.regex.compile([[(\d+)$]])

local frame = trailingDigits:find("sprites/hero_04")
if frame ~= nil then
    print(frame.value, frame.first, frame.last)
end

print(trailingDigits:replaceAll("hero_04 orc_11", "N"))
```

Subjects remain byte strings, including strings that are not valid UTF-8.
Match positions therefore follow Lua's string functions: 1-based, inclusive
byte indices. An empty match has `last == first - 1`.

## Compile a pattern

```nupp
local expression: nupp.Regex = nupp.regex.compile(pattern)
```

`pattern` uses Rust regex syntax and must be UTF-8. NUL bytes are accepted
where the syntax permits them. Malformed syntax or invalid UTF-8 raises an
error.

Rust's Unicode character classes work by default. Inline flags change matching
inside the pattern: `(?i)` enables case-insensitive matching, while `(?-u:.)`
matches one arbitrary byte. Keep the returned expression and reuse it; the Lua
collector releases its native allocation automatically.

Direct use of `nupp.regex.compile` is detected during checking. A build stages
the native regex provider only when the resolved program uses it. See
[Compiler-native features](tooling/build.md#compiler-native-features) for
automatic detection and target overrides.

## `nupp.Regex` API

A compiled expression has the following fields and methods.

### `pattern`

```nupp
expression.pattern: string
```

The original source pattern, unchanged.

### `isMatch`

```nupp
local matched: boolean = expression:isMatch(subject)
```

Reports whether any part of the arbitrary-byte `subject` matches.

### `find`

```nupp
local match: nupp.RegexMatch? = expression:find(subject, init)
```

Finds the first match at or after `init`, or returns nil. The optional `init`
uses `string.find`'s byte-position rules: it defaults to 1, a negative value
counts back from the end, and a value before 1 is clamped to 1. It must be an
integer.

```nupp
local digits = nupp.regex.compile([[\d+]])
local found = assert(digits:find("hp=100"))

assert(found.value == "100")
assert(found.first == 4)
assert(found.last == 6)
```

### `captures`

```nupp
local captures: nupp.RegexCaptures? = expression:captures(subject, init)
```

Finds the first match and every capture group it populated. `init` follows the
same rules as `find`.

`groups` may contain holes when optional groups do not participate. Iterate
from 1 through `groupCount`, rather than using `#groups`. Each named entry
aliases the same `nupp.RegexMatch` stored at its numbered index.

```nupp
local pair = nupp.regex.compile([[(?<key>\w+)=(\d+)]])
local captures = assert(pair:captures("hp=100"))

assert(captures.whole.value == "hp=100")
assert(captures.groups[1].value == "hp")
assert(captures.groups[2].value == "100")
assert(captures.named.key.value == "hp")
```

Capture names are pattern-defined, so the static type of `named` is gradual.
Numbered groups retain their precise `nupp.RegexMatch` type.

### `replace`

```nupp
local output: string = expression:replace(subject, replacement)
```

Replaces the first match. Capture references in `replacement` use `$0` for the
whole match, `$1` for the first group, `$name` or `${name}` for a named group,
and `$$` for one dollar sign. A reference not declared by the pattern expands
to an empty string.

```nupp
local pair = nupp.regex.compile([[(\w+)=(\d+)]])
assert(pair:replace("hp=100 mp=50", "$1: $2") == "hp: 100 mp=50")
```

When nothing matches, it returns the original string unchanged.

### `replaceAll`

```nupp
local output: string = expression:replaceAll(subject, replacement)
```

Replaces every non-overlapping match using the same capture-reference syntax
as `replace`.

```nupp
local digits = nupp.regex.compile([[\d+]])
assert(digits:replaceAll("room 12, floor 3", "#") == "room #, floor #")
```

When nothing matches, it returns the original string unchanged.

## Result records

### `nupp.RegexMatch`

One matched byte range:

| Field | Type | Meaning |
| --- | --- | --- |
| `value` | `string` | Bytes copied from the matched range. |
| `first` | `integer` | First matched byte, using a 1-based index. |
| `last` | `integer` | Inclusive last byte; `first - 1` for an empty match. |
| `index` | `integer` | Capture index, with zero for the whole match. |
| `name` | `string?` | Capture name, or nil for an unnamed group. |

### `nupp.RegexCaptures`

The result of one capture search:

| Field | Type | Meaning |
| --- | --- | --- |
| `whole` | `nupp.RegexMatch` | Group zero, covering the whole match. |
| `groups` | `{nupp.RegexMatch}` | Explicit groups by 1-based index; unmatched groups leave holes. |
| `groupCount` | `integer` | Number of explicit groups, including ones that did not match. |
| `named` | `any` | Matched names mapped to the same values in `groups`. |
