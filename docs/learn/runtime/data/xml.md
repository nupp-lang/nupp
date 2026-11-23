---
order: 136
title: XML
---

# XML

`serde.xml` reads and writes XML in Nupp, with no C library. It has four
surfaces over one cursor:

- a typed codec that decodes elements straight into records and encodes them
  back, with no token objects and no tree;
- a pull reader;
- an element tree;
- a writer that refuses output that would not be well formed.

The default mode is fast and still safe. What costs speed is a named option,
and its cost is measured below.

```nupp
local xml = serde.xml
local record Datapoint
    id: string
    label: string
    values: {number} = {}
end
local points = xml.codec(Datapoint)
local point = points:decode("<Datapoint><id>a</id><label>L</label><values><member>1.5</member></values></Datapoint>")
assert(point.values[1] == 1.5)
assert(points:encode(point) == "<Datapoint><id>a</id><label>L</label><values><member>1.5</member></values></Datapoint>")
```

## What the default reads

- The input is UTF-8, and it is validated as UTF-8.
- References: the five predefined entities and numeric character references,
  checked as XML characters.
- CDATA sections.
- Comments and processing instructions, which are skipped unless a reader asks
  for them.
- End tags, matched on every element that is decoded or read.
- Qualified names, kept as their raw `prefix:local` bytes.
- Name bytes of 0x80 and above, accepted as part of a name.
- Nesting up to a depth limit, 256 unless `maxdepth` says otherwise.

A reference to any other entity is an error in every mode. A DOCTYPE is
skipped by a scan that respects quotes and an internal subset, and nothing it
declares is ever applied. Billion-laughs and external-entity documents are
refused, and no mode reads a file or the network.

A document that declares another encoding, or starts with a UTF-16
byte-order mark, is refused with an error that names the `encoding` option.

## The typed codec

`serde.xml.codec(Record, options)` builds a plan for the record and every
record it reaches. The plan is built once, when the codec is made. Every
member's name is spelled out ahead of time as the patterns that read it:

- A scalar member's pattern reads its start tag, its text in the member's
  lexical form and its end tag in one call.
- The member expected next is tried first, and the expected position advances
  on each hit.
- A member found out of order, or one written with attributes, comments or
  references, takes the general path and gives the same value.

Unknown members are skipped by counting depth.

The mapping follows serde. `serde = serde.Options(...)` applies naming to every
record, and the whitelist, renames, `omitempty` and representations to the
root. [](serde.xml.FieldOptions) adds what XML needs:

| Option | Meaning |
| --- | --- |
| `name` | the element or attribute name |
| `attribute` | read and write the field as an attribute |
| `flattened` | repeat a list's items, or a map's entries, under the field's name, unwrapped |
| `member` | a wrapped list's item element, `member` by default |
| `entry`, `key`, `value` | a map's element names, `entry`, `key` and `value` by default |
| `namespace` | the namespace written as `xmlns` on the field's element, and matched with `namespaces` |
| `timestamp` | `"datetime"` or `"epoch"` for a `number` or `integer` field |
| `base64` | read and write a string field as base64 |
| `omitempty` | leave an empty field out |

`fields` maps the root's fields, and `records` maps a nested declaration's fields
by its name. `name` and `namespace` set the root element, and `wrappers` lists
elements between the root and the record's members, the way an awsQuery
response wraps its result.

`serde.xml.decode(binding, source)` and `encode(binding, value)` take a binding
from [](serde.binding). Each builds the same plan on the first call and caches
it per binding.

`codec:decodefrom(reader)` reads an [](io.Reader) in chunks and closes it.

## The reader

`serde.xml.reader(source, options)` takes a string, or a function that answers
the next chunk. `next()` moves a cursor through start, end, text, comment, PI
and DOCTYPE positions without making a token object. The accessors make strings
only when they are called:

- `name()`, `prefix()`, `localname()` and `space()`;
- `text()`, `attr(name)` and `attributes()`.

`nameis(name)` compares bytes and makes nothing. `skip()` passes over an element
by counting depth.

Chunked input goes through a window that is refilled at token boundaries. A
token can hold at most `maxtokenbytes` past its start, 1 MiB unless given. The
tokens are the same however the input is split.

## The tree and the writer

`serde.xml.parse(source, options)` keeps the elements and their text. `child`,
`children`, `find`, `attr` and `text` look things up by qualified name.

Only with `namespaces = true` can a lookup be given a namespace URI:
`child(localname, uri)`. Without the option, a lookup that passes a URI raises.
Feed code turns namespaces on because publishers spell prefixes as they like.
One Torznab indexer writes `torznab:attr` and another `tz:attr`, and only the
URI says they are the same:

```nupp:fragment
local feed = serde.xml.parse(body, {namespaces = true})
local TORZNAB = "http://torznab.com/schemas/2015/feed"
for item in feed:child("channel"):children("item") do
    local seeders = item:find("attr", TORZNAB, {name = "seeders"})
end
```

`serde.xml.writer(sink)` writes escaped XML into a string, or in chunks to a
sink. It refuses each of these:

- a mismatched end tag;
- an element left open at `finish`;
- an invalid name;
- a character XML does not allow.

A `]]>` inside CDATA is split across two sections.

## Options and their cost

Each option is off by default. The cost is the median decode throughput
against the default, measured on the native core on an M5 Pro Mac at a load
average near 8, on smithy-java's benchmark payloads (`bench/xml`):

| Option | What it adds | GetMetricData L | WideTypes S | WideTypes L | CopyObject M |
| --- | --- | --- | --- | --- | --- |
| (default) | | 65.0 ops/s | 1495 ops/s | 421 ops/s | 10148 ops/s |
| `namespaces = true` | a scope per element that declares one, a URI lookup per name, and matching by URI and local name | -11% | -10% | -17% | -12% |
| `strict = true` | every skipped element parsed, every name classified, every text run checked, the internal subset parsed | -23% | -6% | -10% | -25% |
| `encoding = true`, UTF-16 input | a transcoded copy of the input | -81% | -59% | -61% | -86% |
| `encoding = true`, Windows-1252 input | a transcoded copy of the input | -20% | -8% | -7% | -50% |
| chunked input | the window's refills, and a protected call per token | -22% | +3% | -3% | -14% |

A UTF-8 document read with `encoding = true` is not copied, so it costs only
the scan for its declaration.

The typed codec is 200 to 900 times slower than smithy-java's codec on the
JVM for the same payloads, because the core has no JIT yet. The
comparison is in `bench/xml/README.md`.

## Leniencies of the default against strict

The default accepts these, and strict refuses them. A differential fuzz holds
the default to this list:

1. Elements the typed codec or `skip()` passes over are checked only for
   balance and for their own end tag.
2. Duplicate attributes are not detected.
3. Names are runs of ASCII name characters, colons and bytes of 0x80 and
   above. They are not checked against Unicode's NameStartChar and NameChar
   classes.
4. Attribute values are not normalized. References are decoded, and
   whitespace is kept as written.
5. `]]>` in text is accepted.
6. The document is validated as UTF-8 but not checked against XML's Char
   ranges. Outside character references, C0 controls and U+FFFE and U+FFFF
   pass.
7. These are accepted: comments that hold `--` or end with `-`, processing
   instructions named `xml`, and PI targets not followed by whitespace.
8. A DOCTYPE's internal subset is skipped by a scan that respects quotes and
   brackets. It is not parsed by the grammar.
9. Without `namespaces`, no namespace well-formedness is checked.

Everything else is the same in both modes. That includes:

- trailing content after the root element;
- a missing root;
- unbalanced tags on the decoded path;
- the XML declaration's grammar.

## Errors

A failure is a [](serde.Error) with these fields:

- `byte`, the offset;
- `line` and `column`, computed only when the error is raised;
- `path`, the element path in raw names, such as
  `/GetMetricDataResponse/GetMetricDataResult/MetricDataResults/member[3]`;
- `rule`, the rule that was broken, such as `mismatched-end-tag`,
  `undeclared-entity`, `undeclared-encoding`, `depth-limit`, `invalid-utf8` or
  `invalid-value`.
