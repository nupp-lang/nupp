local parser = require("nupp.compiler.parser")
local cst = require("nupp.compiler.cst")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function parseExpr(src)
   local result = parser.parse("return " .. src)
   local ret = result.root.blocks[1].stats[1]
   return ret.exprs[1], result.errors
end

-- Dumps the expression parse of `src` and asserts it parsed without errors.
local function exprDump(src)
   local e, errors = parseExpr(src)
   assertEq(#errors, 0, "unexpected parse errors for " .. src)
   return cst.dump(e)
end

local function assertRoundtrip(src)
   local result = parser.parse(src)
   assertEq(cst.textOf(result.root), src,
      "round-trip failed for " .. ("%q"):format(src))
   return result
end

local M = {}

function M.switchExpressionsUseDoBoundary()
   local src = table.concat({
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
   }, "\n")
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local first = result.root.blocks[1].stats[1].exprs[1]
   assertEq(first.kind, "switchExpr")
   assertEq(first.cases[1].values[1].kind, "number")
   assertEq(#first.cases[2].values, 2)
   assertEq(first.elseCase.expr.kind, "string")
   local second = result.root.blocks[1].stats[2].exprs[1]
   assertEq(second.cases[1].patternKind, "type")
   assertEq(second.cases[1].binding.text, "circle")
   assertEq(second.cases[1].fields[2].alias.text, "label")
   assertEq(second.cases[1].body.stats[2].kind, "switchYieldStmt")
end

function M.switchAndYieldRemainContextual()
   local src = table.concat({
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
   }, "\n")
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local stats = result.root.blocks[1].stats
   assertEq(stats[3].exprs[1].kind, "call")
   assertEq(stats[4].exprs[1].kind, "call")
   assertEq(stats[5].exprs[1].kind, "call")
   assertEq(stats[6].exprs[1].kind, "switchExpr")
   local body = stats[9].exprs[1].elseCase.body.stats
   assertEq(body[1].kind, "callStmt")
   assertEq(body[2].kind, "callStmt")
   assertEq(body[3].kind, "callStmt")
   assertEq(body[5].kind, "switchYieldStmt")
end

function M.sealedInterfaceModifier()
   local source = table.concat({
      "sealed interface exported.Token end",
      "local sealed interface LocalToken end",
      "global sealed interface GlobalToken end",
      "local interface Outer",
      "   sealed interface NestedToken end",
      "end",
   }, "\n")
   local result = assertRoundtrip(source)
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local stats = result.root.blocks[1].stats
   assertEq(stats[1].sealedTok.text, "sealed")
   assertEq(stats[2].visibility, "local")
   assertEq(stats[2].sealedTok.text, "sealed")
   assertEq(stats[3].visibility, "global")
   assertEq(stats[3].sealedTok.text, "sealed")
   assertEq(stats[4].entries[1].sealedTok.text, "sealed")

   local invalid = parser.parse("local sealed record Token end")
   assertEq(#invalid.errors, 1, "sealed record error")
   assertEq(invalid.errors[1].code, "NUPP1002")
end

function M.cdefUnionAndBitfieldRoundtrip()
   local source = "cdef union Value\n   flags: uint32 : 3\n   number: number\nend\n"
   local result = assertRoundtrip(source)
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local declaration = result.root.blocks[1].stats[1]
   assertEq(declaration.aggregateKind, "union")
   assertEq(declaration.entries[1].bitWidth.text, "3")
end

function M.fileInnerAnnotationsAreRecorded()
   local result = parser.parse("@!internal\n@!nofmt\nlocal x=1\n")
   assertEq(#result.errors, 0, "inner annotations parse")
   assertEq(result.root.documentationInternal, true, "internal marker")
   assertEq(result.root.formatDisabled, true, "nofmt marker")
end

function M.ownershipWordsStayContextual()
   local src = table.concat({
      "local takes, borrows, exclusive, retains, releases, unsafe, owned, borrowed, pinned = 1, 2, 3, 4, 5, 6, 7, 8, 9",
      "function transfer(takes value: voidptr, borrows view: voidptr, exclusive changed: voidptr, retains held: voidptr, releases done: voidptr) end",
      "unsafe do print(takes, borrows, exclusive, retains, releases) end",
      "unsafe()",
   }, "\n")
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local transfer = result.root.blocks[1].stats[2]
   assertEq(transfer.body.params[1].modeTok.text, "takes")
   assertEq(transfer.body.params[2].modeTok.text, "borrows")
   assertEq(transfer.body.params[3].modeTok.text, "exclusive")
   assertEq(transfer.body.params[4].modeTok.text, "retains")
   assertEq(transfer.body.params[5].modeTok.text, "releases")
   assertEq(result.root.blocks[1].stats[3].kind, "unsafeStmt")
   assertEq(result.root.blocks[1].stats[4].kind, "callStmt")
end

-- `new` joins the contextual words: a name follows it on the same line or it is
-- an ordinary identifier. The last two lines are the pair that decides it — a
-- `new` ending a line cannot reach across to the next statement's callee.
function M.newStaysContextual()
   local src = table.concat({
      "local new = 1",
      "print(new)",
      "local built = new Point(x = 1)",
      "local qualified = new m.Point(1, 2)",
      "local held = new",
      "print(held)",
   }, "\n")
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local stats = result.root.blocks[1].stats
   assertEq(stats[3].exprs[1].kind, "newExpr")
   assertEq(stats[4].exprs[1].kind, "newExpr")
   assertEq(stats[5].exprs[1].kind, "name")
end

-- A bare `new T` would be a second spelling of `new T()`, and one spelling per
-- meaning is the reason the keyword exists at all.
function M.newNeedsAConstruction()
   local result = parser.parse("local bare = new Point")
   assertEq(#result.errors, 1, "one error")
   assertEq(result.errors[1].code, "NUPP1004")
   assert(result.errors[1].msg:find("needs a construction", 1, true),
      result.errors[1].msg)
end

function M.borrowedReturnsAcceptMultipleSources()
   local result = parser.parse(
      "local function pair(borrows a: any, borrows b: any): any borrows(a, b) return {a, b} end",
      "test")
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local ret = result.root.blocks[1].stats[1].body.rets[1]
   assertEq(ret.kind, "tborrows")
   assertEq(ret.params[1].text, "a")
   assertEq(ret.params[2].text, "b")
end

-- Sources are a list, and one source is a list of length one, so the parentheses are
-- not optional. The first slot of a result pack is where they read worst — the source
-- list closes just before the comma separating the results — so it is the shape worth
-- pinning.
function M.borrowedSourcesAreAlwaysParenthesised()
   local result = parser.parse(
      "local ref: function(borrows b: any): (any borrows (b), integer)", "test")
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local pack = result.root.blocks[1].stats[1].types[1].returnPack
   assertEq(pack.types[1].kind, "tborrows")
   assertEq(pack.types[1].params[1].text, "b")
   assertEq(#pack.types, 2, "the source list closes before the result separator")

   -- A mode written on a parameter modifies that one parameter and stays bare; only
   -- the source list takes parentheses.
   local bare = parser.parse(
      "local view: function(borrows source: any): any borrows source", "test")
   assert(#bare.errors > 0, "a bare source list is refused")
   assert(bare.errors[1].msg:find("borrow sources", 1, true),
      bare.errors[1].msg)
end

function M.cdefOutputsUseTheOrdinaryBorrowRelation()
   local result = parser.parse(table.concat({
      "cdef function view(borrows left: voidptr, borrows right: voidptr,",
      "   out value: voidptr* borrows (left, right)): Success<int32, 0>",
   }, "\n"), "test")
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local relation = result.root.blocks[1].stats[1].params[3].type
   assertEq(relation.kind, "tborrows")
   assertEq(relation.params[1].text, "left")
   assertEq(relation.params[2].text, "right")
end

function M.resultRelationsAttachToTheirFixedPackSlots()
   local result = parser.parse(table.concat({
      "local forward: function<T>(value: T): (string, T preserves value)",
      "local view: function(borrows source: any): (integer, any borrows (source))",
   }, "\n"), "test")
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg or "")
   local stats = result.root.blocks[1].stats
   assertEq(stats[1].types[1].returnPack.types[2].kind, "tpreserves")
   assertEq(stats[1].types[1].returnPack.types[2].param.text, "value")
   assertEq(stats[2].types[1].returnPack.types[2].kind, "tborrows")
   assertEq(stats[2].types[1].returnPack.types[2].param.text, "source")
end
function M.precedenceArithmetic()
   assertEq(exprDump("1 + 2 * 3"),
      "(binop (number 1) + (binop (number 2) * (number 3)))")
   assertEq(exprDump("-x^2"),
      "(unop - (binop (name x) ^ (number 2)))")
   assertEq(exprDump("not a == b"),
      "(binop (unop not (name a)) == (name b))")
end

function M.precedenceRightAssoc()
   assertEq(exprDump("a .. b .. c"),
      "(binop (name a) .. (binop (name b) .. (name c)))")
   assertEq(exprDump("2 ^ 3 ^ 4"),
      "(binop (number 2) ^ (binop (number 3) ^ (number 4)))")
end

function M.customaryOperators()
   -- The customary spellings parse to the classic nodes, at the classic
   -- precedence, so only the token text records which form was written.
   assertEq(exprDump("a && b || c"),
      "(binop (binop (name a) && (name b)) || (name c))")
   assertEq(exprDump("a and b or c"),
      "(binop (binop (name a) and (name b)) or (name c))")
   assertEq(exprDump("!a != b"),
      "(binop (unop ! (name a)) != (name b))")
   assertRoundtrip("x = a && !b || c != d")
end

function M.shortFunctions()
   assertEq(exprDump("|a, b| -> a + b"),
      "(shortfn | (param a) , (param b) | -> (binop (name a) + (name b)))")
   assertEq(exprDump("x -> x * 2"),
      "(shortfn (param x) -> (binop (name x) * (number 2)))")
   -- `||` is one token; operand position is what makes it an empty list
   -- rather than `or`.
   assertEq(exprDump("|| -> true"),
      "(shortfn || -> (trueExpr true))")
   assertEq(exprDump("a || || -> true"),
      "(binop (name a) || (shortfn || -> (trueExpr true)))")
   assertRoundtrip("local f = || -> true")
   assertRoundtrip("f(|| -> 1)")
   assertRoundtrip("local t = {|| -> 1}")
   assertEq(exprDump("|n: number| -> n"),
      "(shortfn | (param n : (tname number)) | -> (name n))")
   assertEq(exprDump("|a| -> do return a end"),
      "(shortfn | (param a) | -> do (block (returnStmt return (name a))) end)")
   -- as a call argument, the body stops at the argument comma
   assertEq(exprDump("f(x -> x, 1)"),
      "(call (name f) (args ( (shortfn (param x) -> (name x)) , (number 1) )))")
   -- nested/curried
   assertEq(exprDump("a -> b -> a"),
      "(shortfn (param a) -> (shortfn (param b) -> (name a)))")
   -- '|' is still bitwise-or in operator position
   assertEq(exprDump("a | b"), "(binop (name a) | (name b))")
   assertEq(exprDump("|...args| -> args.n"),
      "(shortfn | (param ... args) | -> (dotIndex (name args) . n))")
end

function M.namedVarargs()
   local src = "local function collect(first, ...args: number) "
      .. "return args.n, ... end"
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, "named vararg should parse")
   local body = result.root.blocks[1].stats[1].body
   assert(body.varargParam == body.params[2])
   assertEq(body.varargParam.name.text, "args")

   local spaced = assertRoundtrip("local function bad(... args) end")
   assert(#spaced.errors > 0, "named vararg must be contiguous")
end

function M.continueStatements()
   local result = assertRoundtrip(table.concat({
      "local continue = 1",
      "continue = continue + 1",
      "while true do if continue > 1 then continue end end",
      "for i = 1, 2 do continue end",
      "repeat continue until true",
   }, "\n"))
   assertEq(#result.errors, 0, "valid continue forms should parse")

   local outside = assertRoundtrip("continue")
   assertEq(outside.errors[1].msg, "no loop to continue")
   assert(#assertRoundtrip("while true do continue; end").errors > 0,
      "continue must be the last statement in its block")
   assert(#assertRoundtrip(
      "while true do local function f() continue end end").errors > 0,
      "continue cannot cross a function boundary")
end

function M.returnEndsItsBlock()
   local legal = assertRoundtrip(table.concat({
      "local function f(n)",
      "   if n then return 1 else return 2 end",
      "end",
      "do return end",
      "return f;",
   }, "\n"))
   assertEq(#legal.errors, 0, legal.errors[1] and legal.errors[1].msg or "")

   local trailing = assertRoundtrip("return 1\nlocal function f() end")
   assertEq(#trailing.errors, 1, "the trailing statement is reported")
   assertEq(trailing.errors[1].code, "NUPP1005", "syntax code")
   assertEq(trailing.errors[1].msg,
      "'return' must be the last statement in a block")
   assertEq(trailing.errors[1].line, 2, "caret is on the trailing statement")
   assertEq(trailing.errors[1].col, 1, "caret column")
   assert(trailing.errors[1].help, "the report says what to do")
   -- Reporting does not discard: what follows still parses into the block.
   assertEq(#trailing.root.blocks[1].stats, 2, "both statements are kept")

   assertEq(#assertRoundtrip("return 1\nlocal a = 2\nlocal b = 3").errors, 1,
      "one report for a run of trailing statements, not one each")
   assertEq(#assertRoundtrip("return 1\nlocal a = 2\nreturn 3\nlocal b = 4")
      .errors, 2, "a second return that is not last is reported too")
   assertEq(#assertRoundtrip("local function f() return 1 local x = 2 end")
      .errors, 1, "the rule holds inside a function body")
end

function M.interpolatedStringsParse()
   assertEq(exprDump("`n is ${n}!`"),
      "(istring `n is ${ (name n) }!`)")
   assertEq(exprDump("`${a} + ${b} = ${a + b}`"),
      "(istring `${ (name a) } + ${ (name b) } = ${ (binop (name a) + (name b)) }`)")
   assertEq(exprDump("`t ${ {x = 1} } end`"),
      "(istring `t ${ (tableExpr { (fieldNamed x = (number 1)) }) } end`)")
   -- union in pipe params needs parens
   assertEq(exprDump("|v: (number | string)| -> v"),
      "(shortfn | (param v : (tparen ( (tunion (tname number) | (tname string)) ))) | -> (name v))")
   local result = parser.parse("local s = `broken ${x")
   assert(#result.errors > 0, "unterminated istring must error")
   assertEq(cst.textOf(result.root), "local s = `broken ${x")
end

function M.dedentStringsStayContextualAndLossless()
   assertEq(exprDump("dedent [[\n   ready\n   ]]"),
      "(dedentString dedent [[\n   ready\n   ]])")
   local ordinary = exprDump("dedent[1]")
   assertEq(ordinary, "(bracketIndex (name dedent) [ (number 1) ])")
   assertRoundtrip("local text = dedent [=[\n   ]] stays raw\n   ]=]\n")
end

function M.precedenceBitLayers()
   -- | < ~ < & < shift, and .. binds tighter than shift (Lua 5.3 layering)
   assertEq(exprDump("1 | 2 ~ 3 & 4 << 5"),
      "(binop (number 1) | (binop (number 2) ~ (binop (number 3) & "
      .. "(binop (number 4) << (number 5)))))")
   assertEq(exprDump("a << b .. c"),
      "(binop (name a) << (binop (name b) .. (name c)))")
   assertEq(exprDump("a ~>> 2 >> 1"),
      "(binop (binop (name a) ~>> (number 2)) >> (number 1))")
end

function M.ternary()
   assertEq(exprDump("a ? b : c"),
      "(ternary (name a) ? (name b) : (name c))")
   -- right-associative chaining
   assertEq(exprDump("a ? b : c ? d : e"),
      "(ternary (name a) ? (name b) : (ternary (name c) ? (name d) : (name e)))")
   -- condition binds through or/and first
   assertEq(exprDump("a or b ? c : d"),
      "(ternary (binop (name a) or (name b)) ? (name c) : (name d))")
end

function M.ternaryMethodCallRestriction()
   -- ':' in the second arm belongs to the ternary, not a method call [CS-2]
   assertEq(exprDump("x ? f : o:m()"),
      "(ternary (name x) ? (name f) : (methodCall (name o) : m (args ( ))))")
   -- parenthesized method call in the second arm is fine
   assertEq(exprDump("x ? (o:m()) : y"),
      "(ternary (name x) ? (paren ( (methodCall (name o) : m (args ( ))) )) : (name y))")
end

function M.safeNavigation()
   assertEq(exprDump("t?.a?.b"),
      "(safeIndex (safeIndex (name t) ?. a) ?. b)")
   assertEq(exprDump("t?.[k]"),
      "(safeBracket (name t) ?. [ (name k) ])")
   assertEq(exprDump("f?.(x)"),
      "(safeCall (name f) ?. (args ( (name x) )))")
   -- call sugar takes the operator too
   assertEq(exprDump('f?."lit"'), '(safeCall (name f) ?. (args "lit"))')
   assertEq(exprDump("f?.{1}"),
      "(safeCall (name f) ?. (args (tableExpr { (fieldItem (number 1)) })))")
   -- a method call carries a check on the receiver, on the method, or both
   assertEq(exprDump("o?.:m(x)"),
      "(methodCall (name o) ?. : m (args ( (name x) )))")
   assertEq(exprDump("o:m?.(x)"),
      "(methodCall (name o) : m ?. (args ( (name x) )))")
   assertEq(exprDump("o?.:m?.(x)"),
      "(methodCall (name o) ?. : m ?. (args ( (name x) )))")
   assertRoundtrip("local v = a?.b?.[c]?.d?.:e?.()")
   -- assignment targets and compound assignment accept the operator
   assertRoundtrip("a?.b = 1")
   assertRoundtrip("a?.[k] = 1")
   assertRoundtrip("a?.b += 1")
end

function M.compoundAssignment()
   local ops = {"+=", "-=", "*=", "/=", "//=", "%=", "&=", "|=", "~=",
      "<<=", ">>=", "~>>=", "..="}
   for _, op in ipairs(ops) do
      local src = ("x %s 1"):format(op)
      local result = assertRoundtrip(src)
      assertEq(#result.errors, 0, "compound " .. op .. " must parse")
      assertEq(result.root.blocks[1].stats[1].kind, "compoundAssign", op)
   end
   -- `~=` stays inequality in expression position; only a statement reads it
   -- as xor-assign, and Lua has no assignment expression to confuse the two.
   assertEq(exprDump("a ~= b"), "(binop (name a) ~= (name b))")
   -- `!=` spells inequality and nothing else, so it is not xor-assign even
   -- though it shares a token kind with the operator that is. LuaJIT refuses
   -- `a != b` as a statement; so does this.
   local result = parser.parse("local a = 1\na != 2")
   assert(#result.errors > 0, "!= must not read as a compound assignment")
   assertEq(result.root.blocks[1].stats[2].kind, "errorStmt")
   -- and the message names what was written rather than the kind it folds to
   assertRoundtrip("local a = 1\na != 2")
end

function M.safeMethodCallsAndTheTernary()
   -- [CS-2]: a method call in the second arm needs parentheses. The safe
   -- spellings are no exception, which is what LuaJIT does.
   local result = parser.parse("x = c ? o?.:m() : y")
   assert(#result.errors > 0, "?.: must not parse in the second arm")
   assert(result.errors[1].msg:find("ternary", 1, true), result.errors[1].msg)
   assertEq(#parser.parse("x = c ? (o?.:m()) : y").errors, 0,
      "parenthesized is fine")
   assertRoundtrip("x = c ? o?.:m() : y")
end

function M.suffixesAndCalls()
   assertEq(exprDump("a.b[c]:m(1)"),
      "(methodCall (bracketIndex (dotIndex (name a) . b) [ (name c) ]) "
      .. ": m (args ( (number 1) )))")
   assertEq(exprDump('f"lit"'), '(call (name f) (args "lit"))')
   assertEq(exprDump("f{1}"),
      "(call (name f) (args (tableExpr { (fieldItem (number 1)) })))")
end

function M.statementForms()
   local src = table.concat({
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
   }, "\n")
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, "statement corpus should parse cleanly")
   local kinds = {}
   for _, s in ipairs(result.root.blocks[1].stats) do
      kinds[#kinds + 1] = s.kind
   end
   assertEq(table.concat(kinds, " "),
      "localStmt assignStmt funcStmt localFuncStmt fornumStmt "
      .. "forinStmt whileStmt repeatStmt ifStmt doStmt gotoStmt "
      .. "labelStmt returnStmt")
end

function M.constDeclarations()
   local src = table.concat({
      "const answer: integer = 42",
      "const left, right = 1, 2",
      "const function identity(x: any): any return x end",
   }, "\n")
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, "const declarations should parse cleanly")
   local stats = result.root.blocks[1].stats
   assert(stats[1].isConst and stats[1].kind == "localStmt")
   assert(stats[2].isConst and stats[2].kind == "localStmt")
   assert(stats[3].isConst and stats[3].kind == "localFuncStmt")
   assertEq(stats[1].types[1].kind, "tname")

   -- The soft keyword remains an identifier outside declaration shape.
   assertEq(assertRoundtrip("local const = 1\nconst = const + 1")
      .root.blocks[1].stats[2].kind, "assignStmt")
   assertEq(#assertRoundtrip("const(1)").errors, 0)
end

function M.constFieldDeclarations()
   local src = table.concat({
      "local M = {}",
      "const M.bar = {const BAZ = 123}",
      "const... M.settings = {name = 'nupp', nested = {count = 0}}",
      "return M",
   }, "\n")
   local result = assertRoundtrip(src)
   assertEq(#result.errors, 0, "const field declarations should parse cleanly")
   local stats = result.root.blocks[1].stats
   assert(stats[2].isConst and not stats[2].deepConst)
   assert(stats[2].exprs[1].fields[1].isConst)
   assert(stats[3].isConst and stats[3].deepConst)
   assert(stats[3].exprs[1].fields[1].isConst)
   assert(stats[3].exprs[1].fields[2].value.fields[1].isConst)

   local dynamic = parser.parse("local M = {}\nconst M.x[1] = 2", "test")
   assertEq(dynamic.errors[1].code, "NUPP1005",
      "const fields require a static dotted path")
   local positional = parser.parse("local M = {}\nconst... M.x = {1}", "test")
   assertEq(positional.errors[1].code, "NUPP1005",
      "deep const fields require stable names")
end

function M.comptimeTypeAliasesAreDeclarations()
   local source = table.concat({
      "local comptime type Field = {name: string, read: type?}",
      "comptime type Shared = {readonly value: type}",
      "global comptime type Global = {write: type?}",
      "export comptime type Public = {name: string}",
   }, "\n")
   local result = assertRoundtrip(source)
   assertEq(#result.errors, 0, "comptime aliases should parse cleanly")
   local stats = result.root.blocks[1].stats
   assert(stats[1].kind == "typeAlias" and stats[1].comptimeOnly)
   assert(stats[1].visibility == "local" and stats[1].comptimeTok.text == "comptime")
   assert(stats[2].kind == "typeAlias" and stats[2].visibility == "module")
   assert(stats[3].kind == "typeAlias" and stats[3].visibility == "global")
   assert(stats[4].kind == "exportStmt" and stats[4].stat.comptimeOnly)
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
   assertEq(last.kind, "returnStmt", "return after error should parse")
   assertEq(cst.dump(last.exprs[1]), "(number 99)")
end

function M.strayEndAtTopLevel()
   local result = assertRoundtrip("end return 1")
   assert(#result.errors > 0)
   assertEq(cst.textOf(result.root), "end return 1")
end

function M.syntaxDiagnosticsHaveCodesSpansAndFoundTokens()
   local result = assertRoundtrip("local value =\nlocal next = (1 + )")
   assert(#result.errors >= 2, "both malformed expressions are reported")
   assertEq(result.errors[1].code, "NUPP1004", "expression code")
   assertEq(result.errors[1].length, #"local", "whole token span")
   assert(result.errors[1].msg:find('found "local"', 1, true),
      "message names the recovery token: " .. result.errors[1].msg)
   assertEq(result.errors[2].code, "NUPP1004", "second expression code")

   local unclosed = assertRoundtrip("if true then")
   local last = unclosed.errors[#unclosed.errors]
   assertEq(last.code, "NUPP1002", "missing token code")
   assert(last.msg:find("found end of file", 1, true), last.msg)
end

function M.selfParseClean()
   for _, rel in ipairs({
      "src/nupp/compiler/lexer.nupp", "src/nupp/compiler/cst.nupp", "src/nupp/compiler/parser.nupp",
      "tests/lexertest.lua", "tests/parsertest.lua", "tests/run.lua",
   }) do
      local f = assert(io.open(ROOT .. "/" .. rel))
      local src = f:read("*a")
      f:close()
      local result = parser.parse(src, rel)
      assertEq(#result.errors, 0, "self-parse errors in " .. rel
         .. (result.errors[1] and (": line " .. result.errors[1].line
            .. ": " .. result.errors[1].msg) or ""))
      assertEq(cst.textOf(result.root), src, "self round-trip: " .. rel)
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
   assertEq(#result.errors, 0,
      "nested generic close reported: "
      .. (result.errors[1] and result.errors[1].msg or ""))
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
      assertEq(#result.errors, 0, src .. ": "
         .. (result.errors[1] and result.errors[1].msg or ""))
   end
   local optional = parser.parse(sources[1]).root.blocks[1].stats[1]
   assertEq(optional.types[1].kind, "topt", "the postfix belongs to the outer list")
   assertEq(optional.types[1].inner.kind, "tname")
   local union = parser.parse(sources[2]).root.blocks[1].stats[1]
   assertEq(union.types[1].kind, "tunion")
end

-- An assignment to something that is not a place is reported at that target,
-- not at whatever statement happens to follow the right-hand side.
function M.unassignableTargetIsReportedAtTheTarget()
   local plain = parser.parse("local t = {}\nf() = 1\nprint(2)\n")
   assertEq(#plain.errors, 1, "one error for the call target")
   assertEq(plain.errors[1].msg, "cannot assign to this expression")
   assertEq(plain.errors[1].line, 2, "assignment target line")
   assertEq(plain.errors[1].col, 1, "assignment target column")
   local compound = parser.parse("local t = {}\nt.x, f() += 1\nprint(2)\n")
   assert(compound.errors[1], "a compound assignment to a call went unreported")
   assertEq(compound.errors[1].line, 2, "compound target line")
   local second = parser.parse("local t = {}\nt.x, f() = 1, 2\nprint(2)\n")
   assertEq(#second.errors, 1, "one error for the second target")
   assertEq(second.errors[1].line, 2, "second target line")
   assertEq(second.errors[1].col, 6, "second target column")
end

-- An unmatched second half is still reported rather than silently swallowed.
function M.strayHalfCloseIsReported()
   local result = parser.parse("local w: Box<integer>> = 1\n")
   assertEq(cst.textOf(result.root), "local w: Box<integer>> = 1\n")
   assertEq(#result.errors > 0, true, "a stray > went unreported")
end

return M
