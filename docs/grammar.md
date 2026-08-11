# Grammar

Nupp's syntax is defined by a normative ABNF grammar. It is embedded below
straight from `docs/grammar.abnf` rather than retyped here, so this page can
never drift from the grammar the parser is actually checked against.

Notation is ABNF per RFC 5234 with RFC 7405 case sensitivity. Rule layering
encodes operator precedence and associativity, and the context-sensitive
constructs ABNF cannot express are marked `[CS-n]` and specified in the notes
at the end.

<<< @docs/grammar.abnf
