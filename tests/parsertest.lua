local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local cst = require("nupp.compiler.syntax.cst")
local lexer = require("nupp.compiler.syntax.lexer")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function parseExpr(src)
    local result = parser.parse("return " .. src)
    local ret = result.root.blocks[1].stats[1]
    return ret.exprs[1], result.errors
end

-- Dumps the expression parse of `src` and asserts it parsed without errors.
local function exprDump(src)
    local e, errors = parseExpr(src)
    testAssert.equal(#errors, 0, "unexpected parse errors for " .. src)
    return cst.dump(e)
end

local function assertRoundtrip(src)
    local result = parser.parse(src)
    testAssert.equal(cst.textOf(result.root), src, "round-trip failed for " .. ("%q"):format(src))
    return result
end

local function applyFix(source, fix)
    local edits = {}
    for index, edit in ipairs(fix.edits) do
        edits[index] = edit
    end
    table.sort(edits, function(left, right)
        return left.offset > right.offset
    end)
    for _, edit in ipairs(edits) do
        source = source:sub(1, edit.offset - 1) .. edit.newText .. source:sub(edit.offset + edit.length)
    end

    return source
end

local M = {}

function M.switchExpressionsUseDoBoundary()
    local src = table.concat(
        {
            "local label = switch status do",
            "   case 200 -> 'ok'",
            "   case 301, 302 -> 'redirect'",
            "   else -> 'other'",
            "end",
            "local area = switch shape do",
            "   case is Circle as circle {radius, name as label} -> do",
            "      local scale = 2",
            "      yield radius * scale",
            "   end",
            "   else -> 0",
            "end",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local first = result.root.blocks[1].stats[1].exprs[1]
    testAssert.equal(first.kind, "switchExpr")
    testAssert.equal(first.cases[1].values[1].kind, "number")
    testAssert.equal(#first.cases[2].values, 2)
    testAssert.equal(first.elseCase.expr.kind, "string")
    local second = result.root.blocks[1].stats[2].exprs[1]
    testAssert.equal(second.cases[1].patternKind, "type")
    testAssert.equal(second.cases[1].binding.text, "circle")
    testAssert.equal(second.cases[1].fields[2].alias.text, "label")
    testAssert.equal(second.cases[1].expr.body.stats[2].kind, "yieldStmt")
end

function M.switchAndYieldRemainContextual()
    local src = table.concat(
        {
            "local switch = function(value) return value end",
            "local yield = switch",
            "local a = switch(1)",
            "local b = switch {1}",
            "local c = switch 'x'",
            "local d = switch (1) do case 1 -> 2 else -> 3 end",
            "local e = switch {value = 1} do else -> 4 end",
            "local f = switch 'x' do case 'x' -> 5 else -> 6 end",
            "local g = switch 1 do else -> do",
            "   yield(1)",
            "   yield {1}",
            "   yield 'x'",
            "   local answer = 7",
            "   yield answer",
            "end end",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local stats = result.root.blocks[1].stats
    testAssert.equal(stats[3].exprs[1].kind, "call")
    testAssert.equal(stats[4].exprs[1].kind, "call")
    testAssert.equal(stats[5].exprs[1].kind, "call")
    testAssert.equal(stats[6].exprs[1].kind, "switchExpr")
    local body = stats[9].exprs[1].elseCase.expr.body.stats
    testAssert.equal(body[1].kind, "callStmt")
    testAssert.equal(body[2].kind, "callStmt")
    testAssert.equal(body[3].kind, "callStmt")
    testAssert.equal(body[5].kind, "yieldStmt")
end

function M.sealedInterfaceModifier()
    local source = table.concat(
        {
            "sealed interface exported.Token end",
            "local sealed interface LocalToken end",
            "global sealed interface GlobalToken end",
            "local interface Outer",
            "   sealed interface NestedToken end",
            "end",
        },
        "\n"
    )
    local result = assertRoundtrip(source)
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local stats = result.root.blocks[1].stats
    testAssert.equal(stats[1].sealedTok.text, "sealed")
    testAssert.equal(stats[2].visibility, "local")
    testAssert.equal(stats[2].sealedTok.text, "sealed")
    testAssert.equal(stats[3].visibility, "global")
    testAssert.equal(stats[3].sealedTok.text, "sealed")
    testAssert.equal(stats[4].entries[1].sealedTok.text, "sealed")

    local invalid = parser.parse("local sealed record Token end")
    testAssert.equal(#invalid.errors, 1, "sealed record error")
    testAssert.equal(invalid.errors[1].code, "NUPP1002")
end

-- `sealed` is contextual, as `record` and `type` are: it modifies a declaration only
-- where one follows, and is an ordinary name everywhere else, in plain Lua and in
-- Nupp alike. Level 0 reserves no identifier level 1 did not inherit from Lua.
function M.sealedIsAnOrdinaryNameOutsideADeclaration()
    local sources = {
        "local sealed = 1\nprint(sealed)",
        "local t = {sealed = 1}\nt.sealed = 2\nprint(t.sealed, t:sealed())",
        "local function sealed(sealed) return sealed end\nsealed = nil",
    }
    for _, filename in ipairs({"plain.lua", "typed.nupp"}) do
        for _, src in ipairs(sources) do
            local result = parser.parse(src, filename)
            testAssert.equal(#result.errors, 0, filename .. ": " .. (result.errors[1] and result.errors[1].msg or ""))
            testAssert.equal(cst.textOf(result.root), src)
        end
    end
end

function M.cdefUnionAndBitfieldRoundtrip()
    local source = "cdef union Value\n   flags: uint32 : 3\n   number: number\nend\n"
    local result = assertRoundtrip(source)
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local declaration = result.root.blocks[1].stats[1]
    testAssert.equal(declaration.aggregateKind, "union")
    testAssert.equal(declaration.entries[1].bitWidth.text, "3")
end

-- Nesting past what any pass can walk is a syntax error rather than a Lua stack
-- overflow: five thousand parentheses used to end the process with a traceback.
-- The refused file still round-trips, as one error statement.
function M.nestingTooDeepIsASyntaxError()
    local deep = "return " .. ("("):rep(5000) .. "1" .. (")"):rep(5000) .. "\n"
    local ok, result = pcall(parser.parse, deep)
    assert(ok, "the parser does not throw: " .. tostring(result))
    testAssert.equal(#result.errors, 1, "one error for the whole nesting")
    testAssert.equal(result.errors[1].code, "NUPP1005")
    assert(result.errors[1].msg:find("nested more than 1000 levels deep", 1, true), result.errors[1].msg)
    testAssert.equal(cst.textOf(result.root), deep, "the refused file round-trips")

    local shallow = "return " .. ("("):rep(900) .. "1" .. (")"):rep(900) .. "\n"
    testAssert.equal(#parser.parse(shallow).errors, 0, "nine hundred levels still parse")
    local blocks = ("if x then\n"):rep(5000) .. ("end\n"):rep(5000)
    testAssert.equal(parser.parse(blocks).errors[1].code, "NUPP1005", "blocks are bounded too")
end

function M.fileInnerAnnotationsAreRecorded()
    local result = parser.parse("@!internal\n@!nofmt\nlocal x=1\n")
    testAssert.equal(#result.errors, 0, "inner annotations parse")
    testAssert.equal(result.root.documentationInternal, true, "internal marker")
    testAssert.equal(result.root.formatDisabled, true, "nofmt marker")
end

function M.ownershipWordsStayContextual()
    local src = table.concat(
        {
            "local takes, borrows, exclusive, retains, releases, unsafe, owned, borrowed, pinned = 1, 2, 3, 4, 5, 6, 7, 8, 9",
            "function transfer(takes value: voidptr, borrows view: voidptr, exclusive changed: voidptr, retains held: voidptr, releases done: voidptr) end",
            "@unsafe do print(takes, borrows, exclusive, retains, releases) end",
            "unsafe()",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local transfer = result.root.blocks[1].stats[2]
    testAssert.equal(transfer.body.params[1].modeTok.text, "takes")
    testAssert.equal(transfer.body.params[2].modeTok.text, "borrows")
    testAssert.equal(transfer.body.params[3].modeTok.text, "exclusive")
    testAssert.equal(transfer.body.params[4].modeTok.text, "retains")
    testAssert.equal(transfer.body.params[5].modeTok.text, "releases")
    testAssert.equal(result.root.blocks[1].stats[3].kind, "pragmaStmt")
    testAssert.equal(result.root.blocks[1].stats[3].stat.kind, "doStmt")
    testAssert.equal(result.root.blocks[1].stats[4].kind, "callStmt")
end

-- `new` joins the contextual words: a name follows it on the same line or it is
-- an ordinary identifier. The last two lines are the pair that decides it — a
-- `new` ending a line cannot reach across to the next statement's callee.
function M.newStaysContextual()
    local src = table.concat(
        {
            "local new = 1",
            "print(new)",
            "local built = new Point(x = 1)",
            "local qualified = new m.Point(1, 2)",
            "local held = new",
            "print(held)",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local stats = result.root.blocks[1].stats
    testAssert.equal(stats[3].exprs[1].kind, "newExpr")
    testAssert.equal(stats[4].exprs[1].kind, "newExpr")
    testAssert.equal(stats[5].exprs[1].kind, "name")
end

-- A bare `new T` would be a second spelling of `new T()`, and one spelling per
-- meaning is the reason the keyword exists at all.
function M.newNeedsAConstruction()
    local result = parser.parse("local bare = new Point")
    testAssert.equal(#result.errors, 1, "one error")
    testAssert.equal(result.errors[1].code, "NUPP1004")
    assert(result.errors[1].msg:find("needs a construction", 1, true), result.errors[1].msg)
end

function M.borrowedReturnsAcceptMultipleSources()
    local result = parser.parse(
        "local function pair(borrows a: any, borrows b: any): any borrows(a, b) return {a, b} end",
        "test"
    )
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local ret = result.root.blocks[1].stats[1].body.rets[1]
    testAssert.equal(ret.kind, "tborrows")
    testAssert.equal(ret.params[1].text, "a")
    testAssert.equal(ret.params[2].text, "b")
end

-- Sources are a list, and one source is a list of length one, so the parentheses are
-- not optional. The first slot of a result pack is where they read worst — the source
-- list closes just before the comma separating the results — so it is the shape worth
-- pinning.
function M.borrowedSourcesAreAlwaysParenthesised()
    local result = parser.parse("local ref: function(borrows b: any): (any borrows (b), integer)", "test")
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local pack = result.root.blocks[1].stats[1].types[1].returnPack
    testAssert.equal(pack.types[1].kind, "tborrows")
    testAssert.equal(pack.types[1].params[1].text, "b")
    testAssert.equal(#pack.types, 2, "the source list closes before the result separator")

    -- A mode written on a parameter modifies that one parameter and stays bare; only
    -- the source list takes parentheses.
    local bare = parser.parse("local view: function(borrows source: any): any borrows source", "test")
    assert(#bare.errors > 0, "a bare source list is refused")
    assert(bare.errors[1].msg:find("borrow sources", 1, true), bare.errors[1].msg)
end

function M.cdefOutputsUseTheOrdinaryBorrowRelation()
    local result = parser.parse(
        table.concat(
            {
                "cdef function view(borrows left: voidptr, borrows right: voidptr,",
                "   out value: voidptr* borrows (left, right)): Success<int32, 0>",
            },
            "\n"
        ),
        "test"
    )
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local relation = result.root.blocks[1].stats[1].params[3].type
    testAssert.equal(relation.kind, "tborrows")
    testAssert.equal(relation.params[1].text, "left")
    testAssert.equal(relation.params[2].text, "right")
end

function M.resultRelationsAttachToTheirFixedPackSlots()
    local result = parser.parse(
        table.concat(
            {
                "local forward: function<T>(value: T): (string, T preserves value)",
                "local view: function(borrows source: any): (integer, any borrows (source))",
            },
            "\n"
        ),
        "test"
    )
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local stats = result.root.blocks[1].stats
    testAssert.equal(stats[1].types[1].returnPack.types[2].kind, "tpreserves")
    testAssert.equal(stats[1].types[1].returnPack.types[2].param.text, "value")
    testAssert.equal(stats[2].types[1].returnPack.types[2].kind, "tborrows")
    testAssert.equal(stats[2].types[1].returnPack.types[2].param.text, "source")
end

function M.precedenceArithmetic()
    testAssert.equal(exprDump("1 + 2 * 3"), "(binop (number 1) + (binop (number 2) * (number 3)))")
    testAssert.equal(exprDump("-x^2"), "(unop - (binop (name x) ^ (number 2)))")
    testAssert.equal(exprDump("not a == b"), "(binop (unop not (name a)) == (name b))")
    -- A unary operator binds tighter than every binary one but `^`.
    testAssert.equal(exprDump("-a + b"), "(binop (unop - (name a)) + (name b))")
    testAssert.equal(exprDump("-a * b"), "(binop (unop - (name a)) * (name b))")
    testAssert.equal(exprDump("#t .. s"), "(binop (unop # (name t)) .. (name s))")
    -- `??` binds loosest of all, below `or`.
    testAssert.equal(exprDump("a ?? b and c"), "(binop (name a) ?? (binop (name b) and (name c)))")
    testAssert.equal(exprDump("a or b ?? c"), "(binop (binop (name a) or (name b)) ?? (name c))")
end

function M.precedenceRightAssoc()
    testAssert.equal(exprDump("a .. b .. c"), "(binop (name a) .. (binop (name b) .. (name c)))")
    testAssert.equal(exprDump("2 ^ 3 ^ 4"), "(binop (number 2) ^ (binop (number 3) ^ (number 4)))")
end

function M.customaryOperators()
    -- The customary spellings parse to the classic nodes, at the classic
    -- precedence, so only the token text records which form was written.
    testAssert.equal(exprDump("a && b || c"), "(binop (binop (name a) && (name b)) || (name c))")
    testAssert.equal(exprDump("a and b or c"), "(binop (binop (name a) and (name b)) or (name c))")
    testAssert.equal(exprDump("!a != b"), "(binop (unop ! (name a)) != (name b))")
    assertRoundtrip("x = a && !b || c != d")
end

function M.shortFunctions()
    testAssert.equal(exprDump("|a, b| -> a + b"), "(shortfn | (param a) , (param b) | -> (binop (name a) + (name b)))")
    testAssert.equal(exprDump("x -> x * 2"), "(shortfn (param x) -> (binop (name x) * (number 2)))")
    -- `||` is one token; operand position is what makes it an empty list
    -- rather than `or`.
    testAssert.equal(exprDump("|| -> true"), "(shortfn || -> (trueExpr true))")
    testAssert.equal(exprDump("a || || -> true"), "(binop (name a) || (shortfn || -> (trueExpr true)))")
    assertRoundtrip("local f = || -> true")
    assertRoundtrip("f(|| -> 1)")
    assertRoundtrip("local t = {|| -> 1}")
    testAssert.equal(exprDump("|n: number| -> n"), "(shortfn | (param n : (tname number)) | -> (name n))")
    testAssert.equal(
        exprDump("|a| -> do return a end"),
        "(shortfn | (param a) | -> do (block (returnStmt return (name a))) end)"
    )
    -- as a call argument, the body stops at the argument comma
    testAssert.equal(
        exprDump("f(x -> x, 1)"),
        "(call (name f) (args ( (shortfn (param x) -> (name x)) , (number 1) )))"
    )
    -- nested/curried
    testAssert.equal(exprDump("a -> b -> a"), "(shortfn (param a) -> (shortfn (param b) -> (name a)))")
    -- '|' is still bitwise-or in operator position
    testAssert.equal(exprDump("a | b"), "(binop (name a) | (name b))")
    testAssert.equal(exprDump("|...args| -> args.n"), "(shortfn | (param ... args) | -> (dotIndex (name args) . n))")
end

function M.namedVarargs()
    local src = "local function collect(first, ...args: number) " .. "return args.n, ... end"
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, "named vararg should parse")
    local body = result.root.blocks[1].stats[1].body
    assert(body.varargParam == body.params[2])
    testAssert.equal(body.varargParam.name.text, "args")

    local spaced = assertRoundtrip("local function bad(... args) end")
    assert(#spaced.errors > 0, "named vararg must be contiguous")
end

function M.continueStatements()
    local result = assertRoundtrip(
        table.concat(
            {
                "local continue = 1",
                "continue = continue + 1",
                "while true do if continue > 1 then continue end end",
                "for i = 1, 2 do continue end",
                "repeat continue until true",
            },
            "\n"
        )
    )
    testAssert.equal(#result.errors, 0, "valid continue forms should parse")

    local outside = assertRoundtrip("continue")
    testAssert.equal(outside.errors[1].msg, "no loop to continue")
    assert(
        #assertRoundtrip("while true do continue; end").errors > 0,
        "continue must be the last statement in its block"
    )
    assert(
        #assertRoundtrip("while true do local function f() continue end end").errors > 0,
        "continue cannot cross a function boundary"
    )

    local skipped = assertRoundtrip("repeat if x then continue end local y = 1 until y > 0")
    testAssert.equal(skipped.errors[1].msg, "continue skips local 'y', which the until condition reads")
    testAssert.equal(
        #assertRoundtrip("repeat local y = 1 if x then continue end local z = 2 until y > 0").errors,
        0,
        "a local declared before the continue is in scope for the condition"
    )
end

function M.returnEndsItsBlock()
    local legal = assertRoundtrip(
        table.concat(
            {"local function f(n)", "   if n then return 1 else return 2 end", "end", "do return end", "return f;",},
            "\n"
        )
    )
    testAssert.equal(#legal.errors, 0, legal.errors[1] and legal.errors[1].msg or "")

    local trailing = assertRoundtrip("return 1\nlocal function f() end")
    testAssert.equal(#trailing.errors, 1, "the trailing statement is reported")
    testAssert.equal(trailing.errors[1].code, "NUPP1005", "syntax code")
    testAssert.equal(trailing.errors[1].msg, "'return' must be the last statement in a block")
    testAssert.equal(trailing.errors[1].line, 2, "caret is on the trailing statement")
    testAssert.equal(trailing.errors[1].col, 1, "caret column")
    assert(trailing.errors[1].help, "the report says what to do")
    -- Reporting does not discard: what follows still parses into the block.
    testAssert.equal(#trailing.root.blocks[1].stats, 2, "both statements are kept")

    testAssert.equal(
        #assertRoundtrip("return 1\nlocal a = 2\nlocal b = 3").errors,
        1,
        "one report for a run of trailing statements, not one each"
    )
    testAssert.equal(
        #assertRoundtrip("return 1\nlocal a = 2\nreturn 3\nlocal b = 4").errors,
        2,
        "a second return that is not last is reported too"
    )
    testAssert.equal(
        #assertRoundtrip("local function f() return 1 local x = 2 end").errors,
        1,
        "the rule holds inside a function body"
    )
end

function M.interpolatedStringsParse()
    testAssert.equal(exprDump("`n is ${n}!`"), "(istring `n is ${ (name n) }!`)")
    testAssert.equal(
        exprDump("`${a} + ${b} = ${a + b}`"),
        "(istring `${ (name a) } + ${ (name b) } = ${ (binop (name a) + (name b)) }`)"
    )
    testAssert.equal(
        exprDump("`t ${ {x = 1} } end`"),
        "(istring `t ${ (tableExpr { (fieldNamed x = (number 1)) }) } end`)"
    )
    -- union in pipe params needs parens
    testAssert.equal(
        exprDump("|v: (number | string)| -> v"),
        "(shortfn | (param v : (tparen ( (tunion (tname number) | (tname string)) ))) | -> (name v))"
    )
    local result = parser.parse("local s = `broken ${x")
    assert(#result.errors > 0, "unterminated istring must error")
    testAssert.equal(cst.textOf(result.root), "local s = `broken ${x")
    local trailingEscape = parser.parse("`\\")
    assert(#trailingEscape.errors > 0, "a final istring escape must error")
    testAssert.equal(cst.textOf(trailingEscape.root), "`\\")
end

function M.dedentStringsStayContextualAndLossless()
    testAssert.equal(exprDump("dedent [[\n   ready\n   ]]"), "(dedentString dedent [[\n   ready\n   ]])")
    local ordinary = exprDump("dedent[1]")
    testAssert.equal(ordinary, "(bracketIndex (name dedent) [ (number 1) ])")
    assertRoundtrip("local text = dedent [=[\n   ]] stays raw\n   ]=]\n")
end

function M.precedenceBitLayers()
    -- | < ~ < & < shift, and .. binds tighter than shift (Lua 5.3 layering)
    testAssert.equal(
        exprDump("1 | 2 ~ 3 & 4 << 5"),
        "(binop (number 1) | (binop (number 2) ~ (binop (number 3) & " .. "(binop (number 4) << (number 5)))))"
    )
    testAssert.equal(exprDump("a << b .. c"), "(binop (name a) << (binop (name b) .. (name c)))")
    testAssert.equal(exprDump("a ~>> 2 >> 1"), "(binop (binop (name a) ~>> (number 2)) >> (number 1))")
end

function M.ternary()
    testAssert.equal(exprDump("a ? b : c"), "(ternary (name a) ? (name b) : (name c))")
    -- right-associative chaining
    testAssert.equal(
        exprDump("a ? b : c ? d : e"),
        "(ternary (name a) ? (name b) : (ternary (name c) ? (name d) : (name e)))"
    )
    -- condition binds through or/and first
    testAssert.equal(exprDump("a or b ? c : d"), "(ternary (binop (name a) or (name b)) ? (name c) : (name d))")
end

function M.ternaryMethodCallRestriction()
    -- ':' in the second arm belongs to the ternary, not a method call [CS-2]
    testAssert.equal(exprDump("x ? f : o:m()"), "(ternary (name x) ? (name f) : (methodCall (name o) : m (args ( ))))")
    -- parenthesized method call in the second arm is fine
    testAssert.equal(
        exprDump("x ? (o:m()) : y"),
        "(ternary (name x) ? (paren ( (methodCall (name o) : m (args ( ))) )) : (name y))"
    )
end

function M.safeNavigation()
    testAssert.equal(exprDump("t?.a?.b"), "(safeIndex (safeIndex (name t) ?. a) ?. b)")
    testAssert.equal(exprDump("t?.[k]"), "(safeBracket (name t) ?. [ (name k) ])")
    testAssert.equal(exprDump("f?.(x)"), "(safeCall (name f) ?. (args ( (name x) )))")
    -- call sugar takes the operator too
    testAssert.equal(exprDump('f?."lit"'), '(safeCall (name f) ?. (args "lit"))')
    testAssert.equal(exprDump("f?.{1}"), "(safeCall (name f) ?. (args (tableExpr { (fieldItem (number 1)) })))")
    -- a method call carries a check on the receiver, on the method, or both
    testAssert.equal(exprDump("o?.:m(x)"), "(methodCall (name o) ?. : m (args ( (name x) )))")
    testAssert.equal(exprDump("o:m?.(x)"), "(methodCall (name o) : m ?. (args ( (name x) )))")
    testAssert.equal(exprDump("o?.:m?.(x)"), "(methodCall (name o) ?. : m ?. (args ( (name x) )))")
    assertRoundtrip("local v = a?.b?.[c]?.d?.:e?.()")
    -- assignment targets and compound assignment accept the operator
    assertRoundtrip("a?.b = 1")
    assertRoundtrip("a?.[k] = 1")
    assertRoundtrip("a?.b += 1")
end

function M.compoundAssignment()
    local ops = {"+=", "-=", "*=", "/=", "//=", "%=", "&=", "|=", "~=", "<<=", ">>=", "~>>=", "..="}
    for _, op in ipairs(ops) do
        local src = ("x %s 1"):format(op)
        local result = assertRoundtrip(src)
        testAssert.equal(#result.errors, 0, "compound " .. op .. " must parse")
        testAssert.equal(result.root.blocks[1].stats[1].kind, "compoundAssign", op)
    end
    -- `~=` stays inequality in expression position; only a statement reads it
    -- as xor-assign, and Lua has no assignment expression to confuse the two.
    testAssert.equal(exprDump("a ~= b"), "(binop (name a) ~= (name b))")
    -- `!=` spells inequality and nothing else, so it is not xor-assign even
    -- though it shares a token kind with the operator that is. LuaJIT refuses
    -- `a != b` as a statement; so does this.
    local result = parser.parse("local a = 1\na != 2")
    assert(#result.errors > 0, "!= must not read as a compound assignment")
    testAssert.equal(result.root.blocks[1].stats[2].kind, "errorStmt")
    -- and the message names what was written rather than the kind it folds to
    assertRoundtrip("local a = 1\na != 2")
end

function M.safeMethodCallsAndTheTernary()
    -- [CS-2]: a method call in the second arm needs parentheses. The safe
    -- spellings are no exception, which is what LuaJIT does.
    local result = parser.parse("x = c ? o?.:m() : y")
    assert(#result.errors > 0, "?.: must not parse in the second arm")
    assert(result.errors[1].msg:find("ternary", 1, true), result.errors[1].msg)
    testAssert.equal(#parser.parse("x = c ? (o?.:m()) : y").errors, 0, "parenthesized is fine")
    assertRoundtrip("x = c ? o?.:m() : y")
end

function M.suffixesAndCalls()
    testAssert.equal(
        exprDump("a.b[c]:m(1)"),
        "(methodCall (bracketIndex (dotIndex (name a) . b) [ (name c) ]) " .. ": m (args ( (number 1) )))"
    )
    testAssert.equal(exprDump('f"lit"'), '(call (name f) (args "lit"))')
    testAssert.equal(exprDump("f{1}"), "(call (name f) (args (tableExpr { (fieldItem (number 1)) })))")
end

function M.statementForms()
    local src = table.concat(
        {
            "local a, b = 1, 'two'",
            "a, t.x, t[k] = b, 2, 3",
            "function mod.sub:method(p, ...) return p end",
            "local function helper() end",
            "for n = 1, 10, 2 do print(n) end",
            "for k, v in pairs(t) do _ = k end",
            "while a < 10 do a = a + 1 end",
            "repeat a = a - 1 until a == 0",
            "if a then b() elseif c then d() else e() end",
            "do ; end",
            "goto done",
            "::done::",
            "return a",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, "statement corpus should parse cleanly")
    local kinds = {}
    for _, s in ipairs(result.root.blocks[1].stats) do
        kinds[#kinds + 1] = s.kind
    end
    testAssert.equal(
        table.concat(kinds, " "),
        "localStmt assignStmt funcStmt localFuncStmt fornumStmt "
        .. "forinStmt whileStmt repeatStmt ifStmt doStmt gotoStmt "
        .. "labelStmt returnStmt"
    )
end

function M.constDeclarations()
    local src = table.concat(
        {
            "const answer: integer = 42",
            "const left, right = 1, 2",
            "const function identity(x: any): any return x end",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, "const declarations should parse cleanly")
    local stats = result.root.blocks[1].stats
    assert(stats[1].isConst and stats[1].kind == "localStmt")
    assert(stats[2].isConst and stats[2].kind == "localStmt")
    assert(stats[3].isConst and stats[3].kind == "localFuncStmt")
    testAssert.equal(stats[1].types[1].kind, "tname")

    -- The soft keyword remains an identifier outside declaration shape.
    testAssert.equal(assertRoundtrip("local const = 1\nconst = const + 1").root.blocks[1].stats[2].kind, "assignStmt")
    testAssert.equal(#assertRoundtrip("const(1)").errors, 0)
end

function M.constFieldDeclarations()
    local src = table.concat(
        {
            "local M = {}",
            "const M.bar = {const BAZ = 123}",
            "const... M.settings = {name = 'nupp', nested = {count = 0}}",
            "return M",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, "const field declarations should parse cleanly")
    local stats = result.root.blocks[1].stats
    assert(stats[2].isConst and not stats[2].deepConst)
    assert(stats[2].exprs[1].fields[1].isConst)
    assert(stats[3].isConst and stats[3].deepConst)
    assert(stats[3].exprs[1].fields[1].isConst)
    assert(stats[3].exprs[1].fields[2].value.fields[1].isConst)

    local dynamic = parser.parse("local M = {}\nconst M.x[1] = 2", "test")
    testAssert.equal(dynamic.errors[1].code, "NUPP1005", "const fields require a static dotted path")
    local positional = parser.parse("local M = {}\nconst... M.x = {1}", "test")
    testAssert.equal(positional.errors[1].code, "NUPP1005", "deep const fields require stable names")
end

function M.comptimeTypeAliasesAreDeclarations()
    local source = table.concat(
        {
            "@comptime local type Field = {name: string, read: type?}",
            "@comptime type Shared = {@readonly value: type}",
            "@comptime global type Global = {write: type?}",
            "@comptime export type Public = {name: string}",
        },
        "\n"
    )
    local result = assertRoundtrip(source)
    testAssert.equal(#result.errors, 0, "comptime aliases should parse cleanly")
    local stats = result.root.blocks[1].stats
    for i, stat in ipairs(stats) do
        if stat.kind == "pragmaStmt" then
            stats[i] = stat.stat
        end
    end
    assert(stats[1].kind == "typeAlias" and stats[1].comptimeOnly)
    assert(stats[1].visibility == "local" and stats[1].comptimeTok.text == "comptime")
    assert(stats[2].kind == "typeAlias" and stats[2].visibility == "module")
    assert(stats[3].kind == "typeAlias" and stats[3].visibility == "global")
    assert(stats[4].kind == "exportStmt" and stats[4].stat.comptimeOnly)
end

function M.removedKeywordFormsAreNotMigrationGrammar()
    for _, case in ipairs({
        {source = "local callback: nosuspend function(): nil"},
        {source = "local callback: sendable function(): nil"},
        {source = "local value: comptime type"},
        {source = "comptime function build(): integer return 1 end"},
        {source = "local comptime function build(): integer return 1 end", ordinary = true},
        {source = "local comptime type Field = {name: string}", ordinary = true},
        {source = "nosuspend do end"},
        {source = "noalloc do end"},
        {source = "noraise do end"},
        {source = "local affine interface R end", ordinary = true},
        {source = "local record R terminal close: function(takes self: R): nil end"},
        {source = "local record R readonly value: integer end"},
        {source = "local record R writeonly value: integer end"},
        {source = "local record R private value: integer end"},
        {source = "local record R readonly [integer]: integer end"},
        {source = "local type R = {readonly value: integer}"},
        {source = "local type R = {writeonly [integer]: integer}"},
    }) do
        local result = parser.parse(case.source, "removed-keyword-form.nupp")
        if case.ordinary then
            testAssert.equal(result.root.blocks[1].stats[1].kind, "localStmt", case.source)
        else
            assert(#result.errors > 0, case.source)
        end
        for _, diagnostic in ipairs(result.errors) do
            assert(not diagnostic.fixes or #diagnostic.fixes == 0, case.source .. " still has a migration fix")
        end
    end
    local annotated = assertRoundtrip("local type Surface = {@readonly value: integer, @writeonly [integer]: integer}")
    testAssert.equal(#annotated.errors, 0)
end

function M.recoveryMissingPieces()
    local cases = {
        "local = 5",
        "if x then return 1",
        "f(1,",
        "a @ b",
        "local t = {1, 2,",
        "function bad.() end",
        "x ? y",
        "return 1 +",
    }
    for _, src in ipairs(cases) do
        local result = assertRoundtrip(src)
        assert(#result.errors > 0, "expected errors for: " .. src)
    end
end

function M.recoveryContinuesParsing()
    -- The statement after a broken one must still be recognized.
    local result = assertRoundtrip("local = 5\nreturn 99")
    assert(#result.errors > 0)
    local stats = result.root.blocks[1].stats
    local last = stats[#stats]
    testAssert.equal(last.kind, "returnStmt", "return after error should parse")
    testAssert.equal(cst.dump(last.exprs[1]), "(number 99)")
end

function M.strayEndAtTopLevel()
    local result = assertRoundtrip("end return 1")
    assert(#result.errors > 0)
    testAssert.equal(cst.textOf(result.root), "end return 1")
end

function M.syntaxDiagnosticsHaveCodesSpansAndFoundTokens()
    local result = assertRoundtrip("local value =\nlocal next = (1 + )")
    assert(#result.errors >= 2, "both malformed expressions are reported")
    testAssert.equal(result.errors[1].code, "NUPP1004", "expression code")
    testAssert.equal(result.errors[1].length, #"local", "whole token span")
    assert(
        result.errors[1].msg:find('found "local"', 1, true),
        "message names the recovery token: " .. result.errors[1].msg
    )
    testAssert.equal(result.errors[2].code, "NUPP1004", "second expression code")

    local unclosed = assertRoundtrip("if true then")
    local last = unclosed.errors[#unclosed.errors]
    testAssert.equal(last.code, "NUPP1002", "missing token code")
    assert(last.msg:find("found end of file", 1, true), last.msg)
end

function M.selfParseClean()
    for _, rel in ipairs({
        "src/nupp/compiler/syntax/lexer.nupp",
        "src/nupp/compiler/syntax/cst.nupp",
        "src/nupp/compiler/syntax/parser.nupp",
        "tests/lexertest.lua",
        "tests/parsertest.lua",
        "tests/run.lua",
    }) do
        local f = assert(io.open(ROOT .. "/" .. rel))
        local src = f:read("*a")
        f:close()
        local result = parser.parse(src, rel)
        testAssert.equal(
            #result.errors,
            0,
            "self-parse errors in " .. rel .. (
                result.errors[1] and (": line " .. result.errors[1].line .. ": " .. result.errors[1].msg) or ""
            )
        )
        testAssert.equal(cst.textOf(result.root), src, "self round-trip: " .. rel)
    end
end

-- Two generic closes are one shift token to the lexer. The inner list takes the
-- token and the outer takes a zero-width stand-in, so the source still prints back.
function M.nestedGenericsCloseWithOneShiftToken()
    assertRoundtrip("local a: Box<Box<integer>> = x\n")
    assertRoundtrip("local b: Box<Box<Box<string>>> = x\n")
    assertRoundtrip("local c: Box<Box<Box<Box<string>>>> = x\n")
    assertRoundtrip("local d: Box<Box<integer> > = x\n")
    assertRoundtrip("local e = 8 >> 2\n")
    assertRoundtrip("local f = a >> b >> c\n")
end

function M.nestedGenericsParseWithoutErrors()
    local result = parser.parse("local a: Box<Box<integer>> = x\n")
    testAssert.equal(
        #result.errors,
        0,
        "nested generic close reported: " .. (result.errors[1] and result.errors[1].msg or "")
    )
end

-- The second half of a `>>` closes the outer list whatever follows it: a postfix,
-- a union or intersection, a separator, or a member projection all used to run
-- into the shift token's leftover half and report a missing `>`.
function M.halfClosedGenericsAcceptWhatFollows()
    local sources = {
        "local a: Box<Box<integer>>? = nil\n",
        "local b: Box<Box<integer>> | nil = nil\n",
        "local c: {Box<Box<integer>>, integer} = x\n",
        "local d: Box<Box<integer>> & {x: integer} = x\n",
        "local e: Box<Box<integer>>* = x\n",
        "local f: Box<Box<integer>>[4] = x\n",
        "local g: Box<Box<integer>>.[K] = x\n",
        "local h = obj:m<Box<Box<T>>>()\n",
        "local i = ffi.new<Box<Box<T>>>()\n",
        "local function j<A is Box<Box<A>>>(): nil end\n",
    }
    for _, src in ipairs(sources) do
        local result = assertRoundtrip(src)
        testAssert.equal(#result.errors, 0, src .. ": " .. (result.errors[1] and result.errors[1].msg or ""))
    end
    local optional = parser.parse(sources[1]).root.blocks[1].stats[1]
    testAssert.equal(optional.types[1].kind, "topt", "the postfix belongs to the outer list")
    testAssert.equal(optional.types[1].inner.kind, "tname")
    local union = parser.parse(sources[2]).root.blocks[1].stats[1]
    testAssert.equal(union.types[1].kind, "tunion")
end

-- An assignment to something that is not a place is reported at that target,
-- not at whatever statement happens to follow the right-hand side.
function M.unassignableTargetIsReportedAtTheTarget()
    local plain = parser.parse("local t = {}\nf() = 1\nprint(2)\n")
    testAssert.equal(#plain.errors, 1, "one error for the call target")
    testAssert.equal(plain.errors[1].msg, "cannot assign to this expression")
    testAssert.equal(plain.errors[1].line, 2, "assignment target line")
    testAssert.equal(plain.errors[1].col, 1, "assignment target column")
    local compound = parser.parse("local t = {}\nt.x, f() += 1\nprint(2)\n")
    assert(compound.errors[1], "a compound assignment to a call went unreported")
    testAssert.equal(compound.errors[1].line, 2, "compound target line")
    local second = parser.parse("local t = {}\nt.x, f() = 1, 2\nprint(2)\n")
    testAssert.equal(#second.errors, 1, "one error for the second target")
    testAssert.equal(second.errors[1].line, 2, "second target line")
    testAssert.equal(second.errors[1].col, 6, "second target column")
end

-- A bare return list continues past a comma into anything a type can start with,
-- literal types included: the list once knew fewer starts than the type rule.
function M.bareReturnListsAcceptLiteralTypes()
    local sources = {
        "local function f(): string, 1\n    return \"a\", 1\nend\n",
        "local function g(): string, `x`\n    return \"a\", `x`\nend\n",
        "local function h(): integer, true, nil\n    return 1, true, nil\nend\n",
    }
    for _, src in ipairs(sources) do
        local result = assertRoundtrip(src)
        testAssert.equal(#result.errors, 0, src .. ": " .. (result.errors[1] and result.errors[1].msg or ""))
        local body = result.root.blocks[1].stats[1].body
        testAssert.equal(#body.rets, select(2, src:gsub(",", ",")) / 2 + 1, "every result was read")
    end
end

-- An unmatched second half is still reported rather than silently swallowed.
function M.strayHalfCloseIsReported()
    local result = parser.parse("local w: Box<integer>> = 1\n")
    testAssert.equal(cst.textOf(result.root), "local w: Box<integer>> = 1\n")
    testAssert.equal(#result.errors > 0, true, "a stray > went unreported")
end

-- `if NAME = EXPR then` and `elseif NAME = EXPR then` carry the name and the
-- `=` on the clause, with the expression where a condition goes; a name that
-- is a condition on its own, or the start of one, is still a condition.
function M.ifClausesBindANameFollowedByEquals()
    local src = table.concat(
        {
            "if a = f() then",
            "   print(a)",
            "elseif b = g(a) then",
            "   print(b)",
            "elseif c == 1 then",
            "   print(c)",
            "elseif d then",
            "   print(d)",
            "end",
            "",
        },
        "\n"
    )
    local result = assertRoundtrip(src)
    testAssert.equal(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
    local clauses = result.root.blocks[1].stats[1].clauses
    testAssert.equal(clauses[1].binding.text, "a")
    testAssert.equal(clauses[1].eq.kind, "=")
    testAssert.equal(clauses[1].cond.kind, "call")
    testAssert.equal(clauses[2].binding.text, "b")
    testAssert.equal(clauses[2].cond.kind, "call")
    testAssert.equal(clauses[3].binding, nil, "a comparison is a condition")
    testAssert.equal(clauses[3].cond.kind, "binop")
    testAssert.equal(clauses[4].binding, nil, "a bare name is a condition")
    testAssert.equal(clauses[4].cond.kind, "name")
end

function M.legacyOwnershipAndHandlerFormsHaveMachineApplicableFixes()
    for _, case in ipairs({
        {source = "local raw = @unsafe release owner", fixed = "local raw = @unsafe nupp.release(owner)",},
        {
            source = "local owner = @unsafe adopt raw as affine(integer, close)",
            fixed = "local owner = @unsafe nupp.adopt<affine(integer, close)>(raw)",
        },
        {source = "drop owner", fixed = "nupp.drop(owner)"},
        {
            source = "handle suspension with frame.handler do print('inside') end",
            fixed = "with installation = suspension.install(frame.handler) do print('inside') end",
        },
    }) do
        local parsed = parser.parse(case.source)
        testAssert.equal(#parsed.errors, 1, case.source)
        local fix = parsed.errors[1].fixes and parsed.errors[1].fixes[1]
        assert(fix, "missing fix for " .. case.source)
        local fixed = applyFix(case.source, fix)
        testAssert.equal(fixed, case.fixed)
        testAssert.equal(#parser.parse(fixed).errors, 0, fixed)
    end
end

function M.unsafeOwnershipAlwaysNeedsItsExplicitMarker()
    for _, source in ipairs({
        'local value = release owner',
        'local value = adopt raw as Owner',
        '@unsafe do local value = release owner end',
        '@unsafe do local value = adopt raw as Owner end',
    }) do
        assert(#parser.parse(source).errors > 0, source)
    end
    testAssert.equal(#parser.parse('local unsafe, release, adopt = f, g, h; unsafe() release() adopt()').errors, 0)
end

-- A call's explicit type arguments are committed to by lookahead, so the arguments
-- after them can still be missing. The node keeps its tokens and a missing argument
-- list rather than being dropped along with its `<`.
function M.aFailedExplicitTypeArgumentCallKeepsItsTokens()
    for _, src in ipairs({"<.>(", "<...>(", "f<.>(", "local a = <.>(1)", "f<T>", "obj:m<T>"}) do
        assertRoundtrip(src)
    end
end

-- A token quoted in a message spells bytes from 0x80 up in hex, so the message is
-- valid UTF-8 even when the source is not.
function M.messagesQuoteNonASCIIBytesInHex()
    local result = parser.parse("local \255 = 2", "latin1.nupp")
    for _, e in ipairs(result.errors) do
        testAssert.equal(e.msg:find("[\128-\255]"), nil, "ASCII message: " .. e.msg)
    end
    local named = false
    for _, e in ipairs(result.errors) do
        named = named or e.msg:find('found "\\xFF"', 1, true) ~= nil
    end
    testAssert.equal(named, true, "the byte is named")
end

-- A file's leading inner annotations belong to the file, not a statement: they set
-- flags on the root and keep their tokens beside the tree, and the tree reprints the
-- rest of the file.
function M.innerAnnotationsSitBesideTheTree()
    local src = "@!internal\n@!nofmt\nlocal x = 1\n"
    local result = parser.parse(src, "inner.nupp")
    testAssert.equal(#result.errors, 0)
    testAssert.equal(result.root.documentationInternal, true)
    testAssert.equal(result.root.formatDisabled, true)
    local printed = {}
    for _, token in ipairs(result.root.innerAnnotations) do
        printed[#printed + 1] = lexer.textOf({token})
    end
    local annotations = table.concat(printed)
    testAssert.equal(annotations, "@!internal\n@!nofmt")
    testAssert.equal(annotations .. cst.textOf(result.root), src, "annotations and tree together are the file")
end

return M
