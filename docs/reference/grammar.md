---
order: 660
---

# Grammar

Nupp's syntax is one ABNF grammar, embedded below straight from
`docs/grammar.abnf` rather than retyped. The parser is checked against that
file, so this page cannot drift from what actually parses.

```abnf
funcbody       = "(" [parlist] ")" block "end"
```

Notation is ABNF per RFC 5234 with RFC 7405 case sensitivity, so every quoted
terminal is case-sensitive: read `"if"` as `%s"if"`. Rule layering encodes
operator precedence and associativity, and the context-sensitive constructs
ABNF cannot express are marked `[CS-n]` and specified in the notes at the end.

The grammar is written in two levels. Level 0 is the untyped base language,
which is LuaJIT 3.0's Lua dialect in full. Level 1 adds the typed layer:
annotations, generics, `record`, `interface`, `struct` and `cdef` declarations,
and type annotations on short-function parameters. Both levels are implemented,
and the typed layer takes nothing away from the untyped one.

<<< @docs/grammar.abnf

::: seealso
- [syntax.md](../concepts/syntax.md) for the same constructs with prose and
  worked examples
- [annotations.md](annotations.md) for what each `@annotation` the grammar
  admits means
- [cli.md](cli.md#ast) for `nupp ast`, which prints the tree a file parsed to
- [diagnostics.md](diagnostics.md) for the codes a file that does not parse
  reports
:::
