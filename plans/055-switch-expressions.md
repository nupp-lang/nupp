# Switch expressions and type patterns

Status: planned

## Decision

Add a lexical, expression-valued `switch` with two deliberately closed pattern
families:

1. compile-time scalar values;
2. runtime-testable types with optional whole-value binding and named field
   destructuring.

Every arm uses the existing short-function arrow vocabulary. An expression arm
implicitly supplies its expression. A `do` arm uses contextual `yield` to
supply the switch value, while `return` keeps its existing meaning and exits the
enclosing function.

```nupp
local area = switch shape
    case 0, 1 -> 0

    case is Circle {radius} ->
        math.pi * radius ^ 2

    case is Polygon as polygon {points} -> do
        if #points < 3 then
            return nil, "invalid polygon"
        end

        yield calculateArea(points)
    end

    else -> 0
end
```

The construct lowers lexically to branches, generated locals and merge labels.
It never builds an arm closure or calls a general switch helper. The selector is
evaluated exactly once, cases are tested from top to bottom and there is no
fallthrough.

The canonical formatter indents `case` and `else` one level inside the switch,
and indents arm contents a second level. This is part of the language surface,
not a presentation detail: formatting must never move cases back to the
indentation of the containing statement.

## Why

Nested `if` and `elseif` chains express these decisions today, but they repeat
the subject, distribute narrowing over conditions and make value production an
assignment or an early return. A switch makes the common shape explicit:

- one subject is evaluated once;
- every branch tests that same subject;
- a closed union can be proved exhaustive;
- a type case introduces the narrowed value and selected fields;
- every value-producing path meets at one expression result.

That explicit shape also gives the compiler an optimization boundary it cannot
reliably recover from arbitrary conditionals. Static values may use linear
comparisons, a balanced decision tree or an AOT switch instruction. A group of
nominal record tests may share one runtime type lookup. The source still has
ordered first-match semantics, so an optimization may change the shape of the
tests but never their observable order when a predicate can execute user code.

This is not a general pattern language. Guards, ranges, nested destructuring,
overloadable equality, user-defined deconstruction and fallthrough remain out
of scope. They can be considered separately after the closed forms have stable
semantics, diagnostics and performance data.

## Governing invariants

1. **The selector evaluates once.** Its effects occur before any pattern test,
   and no lowering duplicates or delays them.
2. **First match wins.** Cases have source order. Duplicate and wholly
   unreachable cases are errors rather than silently dead syntax.
3. **Every completing path produces one value.** An expression arm does so
   implicitly. Every reachable path through a block arm must `yield`, `return`,
   raise or otherwise never complete.
4. **`return` remains an early function exit.** It never becomes the switch
   result. Contextual `yield expression` targets the nearest enclosing switch
   arm and does not cross a function boundary.
5. **No arm is a closure.** Arrow syntax is shared vocabulary, not a request to
   allocate a function. A switch in a hot loop must remain trace-recordable.
6. **Patterns are compiler-known.** Static cases use a closed constant grammar.
   Type cases use the existing `is` machinery. Destructuring reads declared
   fields directly and invokes no user hook.
7. **Pattern matching does not consume ownership.** A whole-value binding
   shares the narrowed subject's ownership identity. Field bindings borrow or
   copy according to existing rules and never introduce an implicit move.
8. **An expression is exhaustive.** `else` is required unless subtracting all
   cases from the selector type reaches `never`.
9. **Lua evaluation order survives lowering.** Switches nested in calls,
   constructors, indexes, short-circuit expressions and other switches preserve
   the authored left-to-right and lazy evaluation rules.
10. **Contextual words do not take Lua names away.** `switch(...)`, `case(...)`
    and `yield(...)` remain ordinary calls. The new readings occur only in their
    unambiguous switch positions.
11. **Formatting exposes the tree.** Cases sit inside the switch, arm contents
    sit inside their case and each `end` aligns with the construct it closes.
12. **Regular and AOT execution agree.** They use the same checked pattern plan,
    exhaustiveness result, evaluation order and branch value type.

## User surface

### Static scalar cases

```nupp
local label = switch status
    case 200 -> "ok"
    case 301, 302, 307, 308 -> "redirect"
    case 400, 404 -> "client error"
    else -> "other"
end
```

A static value is an expression accepted by Nupp's closed compile-time constant
evaluator whose result is `nil`, a boolean, a number or a string. The checker
records the value itself; generated code does not reevaluate the case spelling.
Tables, functions, cdata and arbitrary calls are not case values.

The selector's type must admit each value. Repeating the same value is an error,
including when two different constant spellings evaluate to the same value.
Numeric equality follows the primitive runtime equality Nupp generates; there
is no Ruby- or Crystal-style `===` protocol.

### Type cases and bindings

```nupp
local description = switch shape
    case is Circle as circle {radius} ->
        `circle ${circle.name}, radius ${radius}`

    case is Rectangle {width, height as h} ->
        `rectangle ${width} by ${h}`

    else -> "unknown shape"
end
```

The type after `is` must be accepted by the existing runtime `is` operation.
Inside the arm the original selector is narrowed when it is a narrowable name or
dotted path. `as circle` additionally introduces a local holding the narrowed
whole value, which is useful when the selector was an arbitrary expression.

Named destructuring is optional. `{radius}` reads the accessible field and
binds it under the same name; `{height as h}` binds it under another name. The
first version supports direct readable fields only. It does not match by record
field order, recursively destructure another aggregate, call a getter or invoke
a deconstruction method.

Bindings live only in their arm. A binding of an affine subject shares the
subject's ownership entry rather than creating another owner. An owned field
which cannot be safely borrowed or copied is rejected at the pattern with a
repair directing the author to use the narrowed whole value explicitly.

### Expression and block arms

```nupp
local path = switch mode
    case "read" -> inputPath
    case "write" -> outputPath
    else -> defaultPath
end
```

An expression arm contributes that expression's type to the switch result.

```nupp
local value = switch token
    case is NumberToken {text} -> do
        local parsed = tonumber(text)
        if parsed == nil then
            return nil, `invalid number ${text}`
        end

        yield parsed
    end

    else -> 0
end
```

`yield` in a block arm assigns the switch result and transfers control to the
switch merge. It may appear inside nested conditionals or loops. A nested switch
captures its own yields, and a nested ordinary or short function resets the
context. Lua coroutine suspension remains `coroutine.yield`; this construct has
no suspension effect.

A block arm may have several mutually exclusive yields. The control-flow
checker proves that every path either yields or leaves the enclosing function.
A bare `yield`, several yielded expressions and a path which falls off the end
are errors.

### Exhaustiveness

```nupp
local type Mode = "read" | "write"

local permission = switch mode
    case "read" -> "reader"
    case "write" -> "writer"
end
```

No `else` is needed because the two cases subtract the entire selector type.
This applies to closed literal unions and unions of runtime-distinguishable
types. `boolean` can be exhausted by `true` and `false`; an optional can include
a `nil` case.

An open `string`, `number`, `any`, `unknown`, an overlapping refinement the
checker cannot prove complete or any remaining union member requires `else`.
Unlike the existing exhaustiveness lint for an inferred `if` dispatch, a
non-exhaustive switch is a type error: a value expression cannot conditionally
finish without a value.

### Formatting

This is the canonical layout:

```nupp
local result = switch value
    case 1 -> "one"
    case 2 -> do
        log("two")
        yield "two"
    end
    else -> "other"
end
```

The depth rules are exact:

- `switch` begins at the depth of its containing expression or statement;
- `case` and `else` begin at switch depth plus one;
- a continued expression arm begins at switch depth plus two;
- statements in `-> do` begin at switch depth plus two;
- the `end` of a `do` arm aligns with its `case`;
- the `end` of the switch returns to the original switch depth.

Consequently this input:

```nupp
local result=switch value
case 1->"one"
else->"other"
end
```

formats as:

```nupp
local result = switch value
    case 1 -> "one"
    else -> "other"
end
```

Comments immediately before a case use the case indentation. Comments inside
an arm use the arm indentation. Nested switches apply the same relative rule at
each level. The formatter never aligns a case with its containing `switch`,
even when the authored source did.

## Syntax and lossless tree

Update `docs/grammar.abnf` before implementation so the grammar remains the
normative contract. Add these lossless CST families to
`src/nupp/compiler/cst.nupp`:

- `SwitchExpr`;
- `SwitchValueCase`;
- `SwitchTypeCase`;
- `SwitchElseCase`;
- `SwitchPatternBinding`;
- `SwitchYieldStmt`.

Each node retains every authored token and names the children needed by the
checker, formatter, generator and LSP. Add the new node families to the complete
`cst.Node` union and CST pretty-printer coverage.

Extend `src/nupp/compiler/parser.nupp` with:

1. contextual recognition of `switch` in expression position;
2. case recovery boundaries at contextual `case`, reserved `else` and the
   switch-closing `end`;
3. separate static-value and `is` pattern parsers;
4. reuse of `-> expression` and `-> do block end` from short functions;
5. a switch-arm context stack for contextual `yield`;
6. context resets on ordinary and short-function bodies;
7. targeted recovery for a missing selector, arrow, result, arm `end` or switch
   `end`, a duplicate `else` and a case after `else`.

Recognition must preserve valid Lua. A name `switch` followed by call, index or
member suffix remains an ordinary suffixed expression. The contextual switch
form requires its selector to begin on the introducer's line and uses the
following case structure to close the expression. Likewise, `yield expression`
is contextual only inside a switch block arm; `yield(...)` remains a call.

Parser tests cover valid forms, every recovery boundary, contextual-name
compatibility, nested switches and exact parse-print identity for incomplete
source.

## Formatter implementation

`src/nupp/compiler/fmt/init.nupp` computes indentation from CST block depth, not
from token text. Give switch cases an explicit formatter nesting boundary:

- walk each value, type and else case at `block + 1` relative to the switch;
- let a case's block child walk its statements at the resulting `block + 2`;
- leave the switch's closing token at the original block depth;
- mark every case, else arm, block body and closing `end` with the necessary
  forced line break;
- mark `->` as the break point for an expression arm which exceeds the width.

Add `tests/fmtcorpus/statements/switch.nupp` and its expected file. The corpus
must include:

- completely unindented input;
- switches inside functions, `if`, loops and bracketed expressions;
- expression and block arms;
- long value lists, type patterns and result expressions;
- comments before cases, between cases and inside arms;
- comment-only or temporarily incomplete arms;
- nested switches in selectors and arm results;
- an arm `end` immediately followed by another case;
- idempotence after formatting the expected result again.

Focused formatter tests assert the numeric indentation of the first token on
each switch line. Fuzz generation learns the new balanced construct so parse,
format, parse remains stable across random nesting and trivia.

## Checking and control flow

Switch inference belongs with expressions in `src/nupp/compiler/check/expr.nupp`,
but branch state belongs with the control-flow machinery in
`src/nupp/compiler/check/control.nupp`. Extract a shared branch-analysis helper
rather than reproducing the current `if` logic for scopes, ownership snapshots,
path facts and post-branch joins.

For one switch:

1. infer the selector once and record its original type;
2. resolve each constant or runtime-testable type pattern;
3. derive the matched type and subtract it from the remaining type;
4. enter an arm scope under those narrowing facts;
5. declare the optional whole-value and field bindings;
6. check the arm while collecting expression or `yield` result types;
7. record whether the arm completes, leaves or reaches the switch merge;
8. rewind and join ownership and mutation state like mutually exclusive `if`
   branches;
9. union the reachable arm result types;
10. require `else` unless the final remaining type is `never`.

Later cases analyze under the accumulated residue, so their selector and
bindings carry the narrowest provable type. A type case uses exactly the same
runtime-testability decision and true/false narrowing as `e is T`; static
literal cases use the existing equality narrowing and `narrowing.subtract`.

The checker adds stable diagnostics and `explain` entries for:

- a non-static or non-scalar value case;
- a value the selector type cannot contain;
- duplicate scalar values;
- a wholly unreachable value or type case;
- an invalid or runtime-untestable type pattern;
- a missing, private or unreadable destructured field;
- an owned field which cannot be safely bound;
- a `yield` outside a switch block arm;
- a bare or multi-value `yield`;
- a block arm which can complete without yielding;
- a misplaced, repeated or non-final `else`;
- a non-exhaustive switch without `else`.

Expression arms and yielded expressions contribute one ordinary expression
type. An arm which always returns, raises or loops contributes `never`. Existing
return-pack checking remains responsible for a `return` inside an arm.

## Lexical lowering

Do not lower a switch through an immediately invoked function. A function built
inside a loop is both an allocation and a LuaJIT trace-recording failure. Add a
statement-producing expression-lifting plan to `src/nupp/compiler/gen.nupp`.

Conceptually:

```nupp
local result = switch getShape()
    case is Circle {radius} -> radius * radius
    else -> 0
end
```

becomes collision-safe generated Lua of this shape:

```lua
local __switchSubject = getShape()
local __switchResult
if circle_test(__switchSubject) then
    local radius = __switchSubject.radius
    __switchResult = radius * radius
else
    __switchResult = 0
end
local result = __switchResult
```

The actual names come from the generator's reserved-name allocator. A block
arm's `yield` emits a result assignment followed by a `goto` to a private merge
label. Leaving nested lexical scopes is legal; generation must never jump into
one. `return` is emitted unchanged.

A switch is an expression and must work in every expression position before it
ships. The lifting plan therefore preserves:

- left-to-right evaluation of operands, callees, receivers, indexes, arguments
  and constructor fields;
- conditional evaluation of `and`, `or`, `??`, ternary arms and safe-navigation
  suffixes;
- the last-expression pack rules of the surrounding Lua expression while the
  switch itself remains one value;
- local scope for destructured bindings;
- multiple and nested switches in one containing statement;
- source line attribution for the selector, tests, bindings, arm bodies and
  continuation.

Build this as a reusable expression normalization facility rather than a set of
special cases for local assignment and return. Do not accept an expression
position until its ordering and laziness are preserved, and do not use an IIFE
as a fallback.

## Dispatch planning and optimization

The checked switch carries a dispatch plan consumed by both backends. Begin
with direct ordered `if`/`elseif` semantics, then select only transformations
whose predicates are known to be inert.

### LuaJIT backend

- One to three scalar alternatives use linear equality tests.
- A larger ordered integer set may use a balanced comparison tree when all
  tests are primitive and benchmarks show fewer guards on representative hot
  paths.
- String cases remain linear initially. A lookup table is not automatically an
  improvement and must not contain arm functions.
- Adjacent concrete record cases share one `type`, metatable or `__index`
  identity lookup instead of repeating the full nominal `is` expansion.
- Struct cases reuse `ffi.istype`.
- Refined interfaces retain source-order predicate evaluation and are neither
  reordered nor cached when doing so could suppress user code.

No first version adds a BDD, MTBDD, mutable polymorphic inline cache or table of
callbacks. The explicit switch tree supplies the information needed to explore
those later, but each requires workload evidence beyond the ordinary benefit of
clear source and shared type checks.

Add bytecode assertions through `nupp bc --check` proving that a switch inside a
hot loop emits no function construction and remains trace-recordable. Add
benchmarks against equivalent handwritten `if` chains before setting decision
tree thresholds.

### AOT backend

Extend `src/nupp/compiler/aot/lower.nupp` and
`src/nupp/compiler/aot/emit.nupp` with explicit test blocks, arm blocks and a
merge value:

- dense integers may become the backend's native switch or jump table;
- sparse integers use a comparison tree when profitable;
- scalar strings and supported nominal identities use ordered comparisons;
- the result reaches the continuation through a merge slot or SSA value;
- early `return` reaches the enclosing function's return block directly.

Only types already representable in an AOT body participate. An unsupported
selector or pattern receives the existing targeted AOT-boundary diagnostic; it
does not change regular Lua lowering or silently leave the AOT region.

## Tooling

Pattern aliases and field names enter the same definition machinery as local
bindings. This gives definition, references, rename, hover and unused-binding
analysis one source of truth. The original selector retains its narrowing
metadata inside each arm.

Cover the new nodes in:

- semantic token classification;
- LSP definition, references and rename;
- workspace and document symbols where a local binding normally appears;
- AST/CST inspection;
- analysis queries;
- branch coverage instrumentation;
- generated source maps;
- incremental dependency and cache fingerprints.

Coverage counts each case test as a branch and each selected arm as a region.
Instrumentation must preserve selector-once and predicate-order semantics.

## Documentation

Add a compiled section to `src/nupp/compiler/reference.nupp`, regenerate the
committed `docs/reference.md` and update:

- `docs/start/syntax.md` for contextual recognition and grammar;
- `docs/start/tour.md` for one short value and type switch;
- `docs/type-system/unions.md` for exhaustive literal and nominal unions;
- `docs/type-system/narrowing.md` for matched types and accumulated residue;
- ownership documentation for whole-value aliases and field binding;
- AOT and performance documentation for lexical lowering, shared type lookup
  and the no-closure guarantee;
- generated diagnostic documentation for every new error.

The documentation must contain compiled examples of:

1. one and several static values in a case;
2. exhaustive literal unions, booleans and optionals;
3. a required `else` for an open selector;
4. concrete record and struct cases;
5. whole-value binding;
6. same-name and renamed field destructuring;
7. a single-line expression arm;
8. a multiline arm with conditional yields;
9. `return` as an early enclosing-function exit;
10. a nested switch and nearest-switch yield;
11. a selector with a visible side effect proving it runs once;
12. owned values and the refusal to move an owned field implicitly;
13. every deliberately unsupported pattern category;
14. exact canonical formatter indentation.

Every reference example compiles under `tests/referencetest.lua`, and every
cited diagnostic resolves through `nupp explain` with a wrong and corrected
program.

## Test matrix

### Parser and CST

- every value, type, binding, destructuring and arm form;
- nested and expression-position switches;
- contextual-name compatibility with valid Lua calls and assignments;
- missing selector, arrow, result, arm close and switch close;
- case after else and repeated else;
- parse-print identity for valid and incomplete trees.

### Formatter

- unindented cases are moved inward exactly one level;
- cases never move back to the switch's indentation;
- arm statements are one level deeper than their case;
- arm and switch closing tokens align independently;
- nested constructs, comments, width breaks and incomplete source;
- corpus idempotence and formatter fuzz stability.

### Checker

- selector-once type inference and branch narrowing;
- later cases see the remaining type;
- duplicate, incompatible and unreachable patterns;
- exhaustiveness for literals, nil, boolean and nominal unions;
- open and overlapping types require else;
- binding types, scope, privacy and rename identity;
- all block-arm completion paths;
- early return packs and never-producing arms;
- ownership branch joins and affine field refusals;
- effect inference confirms switch yield is not suspension.

### Runtime and generation

- first-match behavior and selector evaluation count;
- scalar, nominal record, struct and refinement tests;
- renamed field values and binding scope;
- nested conditional yields and early returns;
- switches in every expression family, including lazy operators;
- source-map attribution for failures in selectors, tests and arms;
- no generated function in or around the switch;
- bytecode recordability inside a hot loop.

### AOT

- regular and AOT results agree for every supported pattern family;
- dense and sparse integer plans;
- merge values and early returns;
- unsupported patterns receive the intended diagnostic;
- generated artifacts remain deterministic.

### Tooling and documentation

- definition, references, rename, hover and unused bindings;
- coverage branch accounting;
- compiled reference examples and resolved diagnostic codes;
- generated reference and diagnostic files are current.

## Delivery sequence

1. Freeze this syntax and assign diagnostic codes.
2. Add grammar, CST nodes, parser recovery and parse tests.
3. Add formatter depth annotation and its regression corpus before semantic
   work, so every subsequent fixture has canonical layout.
4. Refactor shared branch checking and implement patterns, bindings, yields,
   result inference and exhaustiveness.
5. Add general expression lifting and direct lexical Lua generation.
6. Add bytecode checks, shared nominal tests and benchmark-guided scalar plans.
7. Add AOT control-flow and merge lowering.
8. Complete LSP, coverage, source-map and incremental tooling support.
9. Write the full documentation set and regenerate committed references.
10. Run focused suites, `./bin/nupp test` and `./bin/nupp fixpoint`.

The feature is complete only when cases remain indented under every formatter
entry point, all value-producing paths are proved, Lua lowering allocates no arm
closures, hot-loop bytecode remains recordable, regular and AOT results agree
and every documented example is compiled by the reference test.
