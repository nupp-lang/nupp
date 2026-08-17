# Switch expressions and type patterns

Status: planned

## Decision

Add a lexical, expression-valued `switch` with two deliberately closed pattern
families:

1. statically known scalar values;
2. runtime-testable types with optional whole-value binding and named field
   destructuring.

Every arm uses the existing short-function arrow vocabulary. An expression arm
implicitly supplies its expression. A `do` arm uses contextual `yield` to
supply the switch value, while `return` keeps its existing meaning and exits the
enclosing function.

```nupp
local area = switch shape do
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
It never builds an arm closure or calls a general switch helper. Code already
written inside an arm may still require one of Nupp's existing cleanup or affine
region functions; the switch introduces no new reason for function construction,
and every generated one remains audited by `pluck.loweredFunction`. The selector
is evaluated exactly once, cases are tested from top to bottom and there is no
fallthrough.

Version 1 admits a switch only where its setup is a semantics-preserving prefix
of the containing statement: a single-expression local declaration, assignment
or return; a call statement; and eager, strict-order operand positions beneath
one of those roots. Lazy expression normalization is a separate feature and plan.
Until it exists, a switch under `and`, `or`, `??`, a ternary arm, safe-navigation
gating or another conditionally evaluated position receives a targeted placement
diagnostic. The restriction keeps the no-IIFE guarantee without making switch
syntax depend on a new general control-flow normalization pass.

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
comparisons or a balanced decision tree; the current AOT scalar IR uses an
ordered `If` chain. A group of
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
2. **First match wins.** Cases have source order. Duplicate and provably wholly
   unreachable cases are errors rather than silently dead syntax.
3. **Every completing path produces one value.** An expression arm does so
   implicitly. Every reachable path through a block arm must `yield`, `return`,
   raise or otherwise never complete.
4. **`return` remains an early function exit.** It never becomes the switch
   result. Contextual `yield expression` targets the nearest enclosing switch
   arm and does not cross a function boundary.
5. **The switch adds no closure.** Arrow syntax is shared vocabulary, not a
   request to allocate a function. Existing cleanup and affine-region lowering
   inside an arm keeps its existing generated function and reason. A plain switch
   in a hot loop must remain trace-recordable.
6. **Patterns are compiler-known.** Static cases use a switch-specific closed
   scalar grammar, not the const-generic expression grammar.
   Type cases use the existing `is` machinery. Destructuring reads declared
   fields directly and invokes no user hook.
7. **Pattern matching does not consume ownership.** A whole-value binding
   shares the narrowed subject's ownership identity. Field bindings borrow or
   copy according to existing rules and never introduce an implicit move.
8. **An expression is exhaustive.** `else` is required unless subtracting all
   cases from the selector type reaches `never`.
9. **Lua evaluation order survives lowering.** Every admitted position preserves
   the authored left-to-right evaluation rules. A lazy position is rejected until
   the separate expression-normalization plan can preserve its conditional work.
10. **Contextual words do not take Lua names away.** A `switch` expression is
    recognized by the `do` which terminates its selector. `switch(...)`,
    `switch {...}` and `switch "text"` without that `do` remain ordinary Lua
    calls. The same three call-argument forms after `yield` remain calls. Only
    same-line `yield expression` whose operand does not begin with `(`, `{` or a
    literal string is the switch-result statement.
11. **Formatting exposes the tree.** Cases sit inside the switch, arm contents
    sit inside their case and each `end` aligns with the construct it closes.
12. **Regular and AOT execution agree where AOT admits the construct.** Version 1
    AOT accepts integer-valued cases which lower through the existing scalar IR.
    Other pattern families and early arm returns receive the existing AOT-boundary
    diagnostic.

## User surface

### Static scalar cases

```nupp
local label = switch status do
    case 200 -> "ok"
    case 301, 302, 307, 308 -> "redirect"
    case 400, 404 -> "client error"
    else -> "other"
end
```

A static case has its own deliberately smaller grammar. It accepts `nil`, boolean
and string literals, finite ordinary Lua-number literals with an optional unary
minus, parentheses around one such value, and a name whose checked type already
identifies one exact scalar. It does not reuse `consteval`: that evaluator has
integer, string, boolean and function domains for const generics, admits operators
which are not wanted here, and has neither `nil` nor binary64 number terms.

The first version admits no arithmetic, comparison, concatenation, call, index,
table, function or cdata case expression. A name must reduce to an exact scalar at
the declaration; ordinary immutable runtime values are not static merely because
they were declared with `const`. The checker records the normalized value itself,
and generated code does not reevaluate the case spelling.

Number normalization uses the same finite binary64 value LuaJIT compares at run
time. Consequently `1`, `1.0` and `1e0` are duplicate cases, as are `0` and
`-0.0`. Non-finite values and cdata literal suffixes are rejected. This rule is
local to switch cases and does not widen Nupp's literal-type or const-generic
domains.

The selector's type must admit each value. Repeating the same normalized value
is an error. Numeric equality follows the primitive runtime equality Nupp
generates; there is no Ruby- or Crystal-style `===` protocol.

### Type cases and bindings

```nupp
local description = switch shape do
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
local path = switch mode do
    case "read" -> inputPath
    case "write" -> outputPath
    else -> defaultPath
end
```

An expression arm contributes that expression's type to the switch result.

```nupp
local value = switch token do
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

Only `yield expression` on one physical line is the switch-result statement. It
assigns the result and transfers control to the switch merge. It may appear
inside nested conditionals or loops. A nested switch captures its own yields,
and a nested ordinary or short function resets the context. The formatter never
breaks between `yield` and the first token of its operand.

`yield(...)`, `yield {...}` and `yield "text"` are always ordinary Lua calls,
including inside an arm and with whitespace before their argument. Those are the
three Lua call-sugar argument forms. This preserves the common
`local yield = coroutine.yield` idiom and cannot silently turn suspension into a
switch result. If such a call is the last completing statement of an arm, the
missing-result diagnostic adds: "this is a call; assign its result to a local,
then write `yield value` to produce the switch result." A switch result whose
expression begins with `(`, `{` or a literal string likewise uses a local first.
Switch-result yield itself has no suspension effect; coroutine suspension remains
the call to `coroutine.yield` or an alias of it.

A block arm may have several mutually exclusive yields. The control-flow
checker proves that every path either yields or leaves the enclosing function.
A bare `yield`, several yielded expressions, an operand beginning on the next
line and a path which falls off the end are errors.

### Version 1 expression placement

The first release accepts a switch under statement roots whose setup can be
emitted before that statement without changing whether it runs:

```nupp
local label = switch code do
    case 200 -> "ok"
    else -> "other"
end

result = format("status: %s", switch code do
    case 200 -> "ok"
    else -> "other"
end)

return switch code do
    case 200 -> "ok"
    else -> "other"
end
```

The containing local declaration, assignment or return has one expression; a
call statement may contain switches in its eager callee, receiver or arguments.
Eager operands beneath those roots are accepted with their preceding effects
captured in order.

Conditionally evaluated positions wait for general expression normalization:

```nupp
-- version 1 diagnostic: the switch is in a lazy operand
local selected = ready and switch code do
    case 200 -> "ok"
    else -> "other"
end
```

The same targeted diagnostic covers `or`, `??`, ternary arms, safe-navigation
gates and other placements whose setup cannot be an unconditional statement
prefix. It points to `plans/056-expression-normalization.md`. There is no hidden
IIFE fallback.

### Exhaustiveness

```nupp
local type Mode = "read" | "write"

local permission = switch mode do
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
Unlike the existing suppressible `NUPP2107` `exhaustiveness` lint for an inferred
`if` dispatch, a non-exhaustive switch receives a new non-suppressible semantic
diagnostic: a value expression cannot conditionally finish without a value. It
cannot be disabled with `@allow("exhaustiveness")`.

### Formatting

This is the canonical layout:

```nupp
local result = switch value do
    case 1 -> "one"
    case 2 -> do
        log("two")
        local result = "two"
        yield result
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

The selector-closing `do` makes the switch independent of physical lines. The
formatter may break at designated points inside a long selector, but keeps `do`
on the selector's final logical line. Contextual `yield` and the first token of
its operand remain unbreakable because that form is still line-sensitive. The
formatter never creates source which would parse under a different contextual
reading on the next run.

Consequently this input:

```nupp
local result=switch value do
case 1->"one"
else->"other"
end
```

formats as:

```nupp
local result = switch value do
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

1. contextual recognition of `switch` in expression position through the `do`
   which terminates its selector;
2. case recovery boundaries at contextual `case`, reserved `else` and the
   switch-closing `end`;
3. a dedicated static-value parser which treats `->` as a hard terminator and
   never delegates a trailing name to `parseShortfn`;
4. a dedicated type-pattern parser whose type parse stops before pattern `as`
   and `{`, rather than consuming either as part of a neighboring expression or
   type production;
5. reuse of `-> expression` and `-> do block end` from short functions only
   after the case parser has consumed the arrow;
6. a switch-arm context stack for same-line contextual `yield expression`;
7. context resets on ordinary and short-function bodies;
8. targeted recovery for a missing selector, arrow, result, arm `end` or switch
   `end`, a duplicate `else` and a case after `else`.

The hard arrow boundary is required for both `case MAX -> 0` and
`case 0, 1 -> 0`: ordinary expression parsing would otherwise recognize the
last `name -> expression` as a short function. The case parser owns commas and
the arrow and builds scalar nodes directly.

Recognition must preserve valid Lua. A name `switch` followed by call, index or
member suffix remains an ordinary suffixed expression unless a same-level `do`
follows the complete selector. The `do` is a required, unambiguous selector
terminator, so `switch (value) do`, `switch "value" do`, table selectors and
multiline selectors all work without reserving the name. Without `do`, each is
the ordinary Lua expression it was before. Likewise, `yield expression`
is contextual only inside a switch block arm, only when its first operand token
is on the same line and only when that token is not `(`, `{` or a literal string.
Those three forms remain Lua calls. The formatter marks both contextual pairs
unbreakable so formatting cannot change which grammar recognizes them.

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
- keep the selector-closing `do` on the final logical selector line;
- mark `->` as the break point for an expression arm which exceeds the width.

Add `tests/fmtcorpus/short-functions/switch.nupp` and its expected file. The
arrow-arm layout is closest to the existing short-function corpus, even though
the switch itself is an expression rather than a function. The corpus
must include:

- completely unindented input;
- switches inside functions, `if`, loops and bracketed expressions;
- expression and block arms;
- long value lists, type patterns and result expressions;
- comments before cases, between cases and inside arms;
- comment-only or temporarily incomplete arms;
- nested switches in selectors and arm results;
- an arm `end` immediately followed by another case;
- over-width switch selectors which break internally before their terminating
  `do`, and yielded expressions which prove the introducer/operand pair never
  separates;
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
runtime-testability decision and true/false narrowing as `e is T`; reuse
`check/expr.nupp`'s existing `provenStatically` and `refutedStatically` answers.
Static literal cases use the existing equality narrowing and
`narrowing.subtract`.

"Wholly unreachable" is reported only when those existing proofs refute the
case or the accumulated residue is `never`. A `where`-refined interface can run
a predicate whose overlap is not generally decidable; the checker preserves its
ordered runtime test and does not claim it is unreachable without a proof.

The checker adds stable diagnostics and `explain` entries for:

- a non-static or non-scalar value case;
- a value the selector type cannot contain;
- duplicate scalar values;
- a provably wholly unreachable value or type case;
- an invalid or runtime-untestable type pattern;
- a missing, private or unreadable destructured field;
- an owned field which cannot be safely bound;
- a `yield` outside a switch block arm;
- a bare or multi-value `yield`;
- a block arm which can complete without yielding;
- a misplaced, repeated or non-final `else`;
- a non-exhaustive switch without `else`.

The last item receives a new non-suppressible semantic code. It is not routed
through the lint registry and is not the suppressible `NUPP2107` diagnostic.

Expression arms and yielded expressions contribute one ordinary expression
type. An arm which always returns, raises or loops contributes `never`. Existing
return-pack checking remains responsible for a `return` inside an arm.

## Lexical lowering

Do not lower a switch through an immediately invoked function. A function built
inside a loop is both an allocation and a LuaJIT trace-recording failure. Add a
statement-producing expression-lifting plan to `src/nupp/compiler/gen.nupp`.

Conceptually:

```nupp
local result = switch getShape() do
    case is Circle {radius} -> radius * radius
    else -> 0
end
```

becomes collision-safe generated Lua of this shape:

```lua
local __switchResult0
do
    local __switchSubject = getShape()
    if circle_test(__switchSubject) then
        local radius = __switchSubject.radius
        __switchResult0 = radius * radius
    else
        __switchResult0 = 0
    end
end
local result = __switchResult0
```

The actual names come from the generator's reserved-name allocator. Extend the
existing `pluck` planning boundary instead of pretending it is already a general
normalizer. Version 1 roots are:

- a local declaration with exactly one initializer expression;
- an assignment with exactly one target and value expression;
- a return with exactly one expression;
- a call statement whose eager callee, receiver or argument tree contains a
  switch.

Beneath one of those roots, lifting may walk eager, strict-order operands. It
captures preceding effectful operands in temporaries, evaluates the switch and
then resumes the containing expression. It does not cross `and`, `or`, `??`, a
ternary branch, a safe-navigation gate or any other child whose evaluation is
conditional. Those locations receive the new switch-placement diagnostic and
point to `plans/056-expression-normalization.md`.

The restricted planner still preserves the last-expression pack rules of the
containing statement, local pattern scope, multiple switches whose lifetimes do
not overlap and source lines for the selector, tests, bindings, arm bodies and
continuation. It never falls back to an IIFE.

### Cleanup extents and switch completion

A plain result assignment followed by `goto` is valid only when it does not
cross an active cleanup extent. `with` and other affine regions currently lower
through protected generated functions: `return`, escaping `break`, `continue`
and `goto` become completion sentinels so cleanup runs before control continues.
A switch yield must join that protocol.

Give every lowered switch a private completion identity. A yield which crosses
an active cleanup region returns a switch-completion tag and packed value through
the region. Each intervening region runs its cleanup, then either propagates the
tag to its parent or, at the region containing the target switch, assigns the
switch result and continues at the merge. A yield which crosses no region may use
the direct assignment and private merge label. `return` keeps using the existing
packed-return path unchanged.

Any protected function already required by the arm passes an existing explicit
reason to `pluck.loweredFunction`. The switch itself adds no new lowering reason;
an unexplained function construction in a loop remains a compiler error.

Test yields from inside one and several nested `with` extents, successful and
failing cleanup, affine captures, and a switch nested wholly inside a region.
Every path must clean up exactly once before the result becomes visible.

### Temporary-slot pressure

Do not allocate two function-lifetime locals for every switch site. Selector and
pattern locals live in a generated lexical `do` scope and die at its merge.
Result temporaries come from a planner-owned scratch pool and are reused after
their continuation consumes them. The number of result slots is the maximum
simultaneously live lifted switches in the function, not the number of switch
sites.

The planner tracks active generated locals against LuaJIT's local limit. If
nesting and preceding eager operands exhaust the remaining budget, report a
targeted lowering diagnostic instead of emitting Lua which later fails to load.
Do not spill affine values through an untracked table. A stress test with
hundreds of sequential switches proves slot reuse, and a deep-nesting test proves
the diagnostic occurs before the backend limit.

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

Version 1 follows the scalar IR which exists rather than designing against a
future CFG. `scalarIR.Statement` has `Let`, `Assign` and `If`, but no return
statement, and a native helper body is currently one matching source return
list. Therefore AOT accepts only integer-valued switch cases which can lower as
an ordered `If` chain assigning one merge `Let`/`Assign` slot before the helper's
existing final result expression.

Strings, nominal records, metatables, `where` predicates and early `return`
inside an arm are outside the current AOT domain and receive the existing
targeted AOT-boundary diagnostic. Adding early exits to scalar IR is a separate
feature, not part of this syntax plan.

Nupp `integer` currently lowers to binary64 in AOT, so density alone cannot
justify a C `switch` or jump table. Version 1 emits scalar equality comparisons.
A later optimization may use a native switch only for a selector already proved
to have an integral backend representation, or after a separately verified exact
conversion. Regular Lua lowering and checking are unchanged when AOT refuses a
case family.

## Complete expression-kind audit

Adding a CST expression is repository-wide work. Before declaring parser support
complete, inventory every dispatch on a peer such as `castExpr` and classify the
new node explicitly. At minimum this includes:

- `src/nupp/compiler/analysis.nupp`;
- `src/nupp/compiler/optimize.nupp`;
- `src/nupp/compiler/comptime.nupp`;
- `src/nupp/compiler/check/init.nupp`;
- `src/nupp/compiler/check/functions.nupp`;
- `src/nupp/compiler/check/ownership.nupp`;
- `src/nupp/compiler/lsp/semantic.nupp`;
- the parser, CST, checker, formatter, generator and AOT modules already named.

`analysis` and ownership walks visit the selector, patterns, bindings and every
arm. Optimization may fold a statically selected inert value arm, but must not
erase selector effects or reorder refined predicates. Function and effect walks
treat a switch arm as lexical code in the enclosing function, except that nested
functions retain their normal boundary.

Comptime supports value-pattern switches with expression arms: evaluate the
selector once, normalize it with the same switch-scalar rules, choose the first
matching arm and evaluate that expression. Type patterns and `do` arms receive
specific comptime diagnostics in version 1 rather than falling through to the
generic "a switchExpr expression" message. Supporting their narrowing and
control signals can follow without changing runtime semantics.

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
- the switch-specific scalar grammar, numeric duplicate rules, v1 placement
  boundary and the `yield expression` versus `yield(...)` distinction;
- ownership documentation for whole-value aliases and field binding;
- AOT and performance documentation for lexical lowering, shared type lookup
  and the no-new-closure guarantee;
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
14. an unsupported lazy placement and its repair;
15. `yield(...)` remaining an ordinary coroutine-alias call;
16. exact canonical formatter indentation.

Every reference example compiles under `tests/referencetest.lua`, and every
cited diagnostic resolves through `nupp explain` with a wrong and corrected
program.

## Test matrix

### Parser and CST

- every value, type, binding, destructuring and arm form;
- `case MAX ->` and the final value of `case 0, 1 ->` stop before the arrow and
  never become short functions;
- a type pattern stops before `as` and `{`;
- number normalization, including `1` versus `1.0`, signed zero, non-finite and
  cdata-literal rejection;
- nested and expression-position switches;
- contextual-name compatibility with valid Lua calls and assignments, including
  a local coroutine alias named `yield`;
- missing selector, arrow, result, arm close and switch close;
- case after else and repeated else;
- parse-print identity for valid and incomplete trees.

### Formatter

- unindented cases are moved inward exactly one level;
- cases never move back to the switch's indentation;
- arm statements are one level deeper than their case;
- arm and switch closing tokens align independently;
- nested constructs, comments, width breaks and incomplete source;
- over-width selectors retain their terminating `do`, and over-width contextual
  yields never separate `yield` from its operand;
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
- switches in each admitted statement root and eager operand family;
- every lazy or otherwise unsupported placement receives the targeted diagnostic;
- yields crossing one and several cleanup extents preserve results, failures and
  exactly-once cleanup;
- hundreds of sequential switches reuse result slots, while excessive
  simultaneous liveness receives the pre-backend diagnostic;
- source-map attribution for failures in selectors, tests and arms;
- no generated function attributable to a plain switch, while an existing
  region function inside an arm retains its audited lowering reason;
- bytecode recordability inside a hot loop.

### AOT

- regular and AOT results agree for integer-valued cases;
- ordered scalar `If` lowering with a `Let`/`Assign` merge;
- strings, type patterns and early arm returns receive the intended diagnostic;
- no C switch is emitted for a binary64 `integer` merely because cases are dense;
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
5. Add restricted eager-position lifting, cleanup-completion transport, slot reuse
   and direct lexical Lua generation.
6. Audit every expression-kind dispatcher, including explicit comptime behavior.
7. Add bytecode checks, shared nominal tests and benchmark-guided scalar plans.
8. Add AOT integer-case `If` and merge lowering with explicit boundary refusals.
9. Complete LSP, coverage, source-map and incremental tooling support.
10. Write the full documentation set, regenerate committed references and run
    focused suites, `./bin/nupp test` and `./bin/nupp fixpoint`.

The feature is complete only when cases remain indented under every formatter
entry point, all value-producing paths are proved, Lua lowering adds no arm
closures, cleanup-crossing yields run every cleanup, temporary slots are reused,
plain hot-loop bytecode remains recordable, accepted regular and AOT results
agree and every documented example is compiled by the reference test.
