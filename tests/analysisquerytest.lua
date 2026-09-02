-- The question surface `nupp.compiler.analysis` exposes, tested directly rather than through
-- the passes that ask. A pass declining is not evidence about which question said no,
-- and the whole reason these moved out of the provers is so that one answer serves
-- several callers -- which is only worth anything if the answer itself is pinned.
local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.env")
local analysis = require("nupp.compiler.analysis")
local cst = require("nupp.compiler.cst")

-- One environment for the whole suite.
--
-- Every case checks against an environment built exactly this way, and
-- building one means checking the prelude from source. Per case that was
-- most of what this suite cost; the cases share it the way the other
-- checker suites do.
local sharedEnv = envMod.new(".")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Parse, check, and hand back the query surface beside the tree.
local function analysed(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   check.check(result, "test.g.nupp", sharedEnv, {})
   local queries = analysis.queries(result.analysis)
   assert(queries, "the run produced no queries")
   return queries, result
end

-- The first name token spelling `text` anywhere in the tree.
local function findName(node, text)
   if not node then
      return nil
   end
   if cst.isToken(node) then
      return node.kind == "name" and node.text == text and node or nil
   end
   for _, child in ipairs(node) do
      local found = findName(child, text)
      if found then return found end
   end
   return nil
end

local function findKind(node, kind)
   if not node or cst.isToken(node) then
      return nil
   end
   if node.kind == kind then
      return node end
   for _, child in ipairs(node) do
      local found = findKind(child, kind)
      if found then return found end
   end
   return nil
end

local function findConstructors(node, out)
   out = out or {}
   if not node or cst.isToken(node) then
      return out
   end
   if node.constructorEntry then
      out[#out + 1] = node
   end
   for _, child in ipairs(node) do findConstructors(child, out) end
   return out
end

local function findMethods(node, out)
   out = out or {}
   if not node or cst.isToken(node) then
      return out
   end
   if node.kind == "methodCall" and node.methodEntry then
      out[#out + 1] = node
   end
   for _, child in ipairs(node) do findMethods(child, out) end
   return out
end

local test = {}

function test.visibleSeparatesUnknownFromForeign()
   local queries = analysed("local x = 1\n")
   local ok, why = queries.visible(nil)
   assertEq(ok, false, "a callee that did not resolve is not visible")
   assertEq(why, "the callee is not known here", "and says which")

   ok, why = queries.visible({top = true})
   assertEq(ok, false, "a summary that gave up is not visible")
   assertEq(why, "the callee reaches code with unknown effects", "and says which")

   ok, why = queries.visible({external = true})
   assertEq(ok, false, "a foreign body is not visible")
   assertEq(why, "the callee's body is foreign", "and says which")

   assertEq(queries.visible(analysis.summary()), true, "an inferred summary is")
end

function test.freeNamesTheEffectItFound()
   local queries = analysed("local x = 1\n")
   local clean = analysis.summary()
   assertEq(queries.free(clean, {"yields", "raises"}), true, "reaches neither")

   local yielding = analysis.summary()
   yielding.yields = true
   local ok, why = queries.free(yielding, {"yields"})
   assertEq(ok, false, "a flag disqualifies")
   assertEq(why, "the callee yields", "named in the reason")
   assertEq(queries.free(yielding, {"raises"}), true,
      "and only the kinds the caller asked about")

   local writing = analysis.summary()
   writing.writes["values[*]"] = true
   ok, why = queries.free(writing, {"writes"})
   assertEq(ok, false, "a non-empty list disqualifies")
   assertEq(why, "the callee writes values[*]", "with the path in the reason")
end

function test.knownResolvesANameToItsCallee()
   local queries, result = analysed([[
local function helper(): integer
    return 1
end

local value = helper()
return value
]])
   -- The call's name, not the declaration's: resolution is what is under test.
   local call = findKind(result.root, "call")
   local tok = call and call.obj and (call.obj.token or call.obj.name)
   local known = queries.known(tok)
   assert(known, "the callee resolved")
   assert(known.summary, "and carries a summary")
   assertEq(queries.visible(known.summary), true, "which is visible")
   assertEq(queries.known(nil), nil, "and nil resolves to nothing")
end

-- Walking a whole assignment target in "target context" suppressed every read
-- under it, so `p[q] = v` never recorded q and a contract missing it verified.
function test.anAssignmentTargetsKeysAreRead()
   local src = [[
local function put(p: {[string]: integer}, q: string, v: integer)
    p[q] = v
end
put({}, "k", 1)
]]
   local queries, result = analysed(src)
   local call = findKind(result.root, "call")
   local known = queries.known(call and call.obj and call.obj.token)
   assert(known, "the callee resolved")
   assertEq(known.summary.reads.q, true, "the key is read")
   assertEq(known.summary.reads.v, true, "the value is read")
   assertEq(known.summary.reads.p, nil, "the assigned table itself is not")
   assertEq(known.summary.writes["p[*]"], true, "and it is written")

   local contracted = parser.parse(
      '@effects(reads = {"v"}, writes = {"p[*]"}, shapes = {"p"})\n' .. src, "test.g.nupp")
   local diags = check.check(contracted, "test.g.nupp", sharedEnv, {})
   local found
   for _, diag in ipairs(diags) do
      if diag.code == "NUPP2112" then found = diag.msg end
   end
   assert(found and found:find('reads = "q"', 1, true),
      "a contract without the key is refused: " .. tostring(found))
end

function test.calleeUsesTheSelectedConstructorSummary()
   local queries, result = analysed([[
local record Choice
    value: string
    constructor(self, value: string)
        self.value = value
    end
    constructor(self, value: integer)
        coroutine.yield()
        self.value = tostring(value)
    end
end

local text = new Choice("ready")
local number = new Choice(42)
return text, number
]])
   local calls = findConstructors(result.root)
   assertEq(#calls, 2, "both constructor calls selected a body")
   local text = queries.callee(calls[1])
   local number = queries.callee(calls[2])
   assert(text and number and text ~= number,
      "the query resolves distinct constructor bodies")
   assertEq(text.summary.yields, false, "the first body's summary stays pure")
   assertEq(number.summary.yields, true, "the second body's yield is selected")
end

function test.calleeUsesTheSelectedMethodOverloadSummary()
   local queries, result = analysed([[
local record Choice
    function choose(self, value: string): string
        return value
    end
    function choose(self, value: integer): string
        coroutine.yield()
        return tostring(value)
    end
end

local choice = new Choice()
local text = choice:choose("ready")
local number = choice:choose(42)
return text, number
]])
   local calls = findMethods(result.root)
   assertEq(#calls, 2, "both method calls selected a body")
   local text = queries.callee(calls[1])
   local number = queries.callee(calls[2])
   assert(text and number and text ~= number,
      "the query resolves distinct overloaded method bodies")
   assertEq(text.summary.yields, false, "the first body's summary stays pure")
   assertEq(number.summary.yields, true, "the second body's yield is selected")
end

function test.calleeKeepsInheritedMethodOverloadProvenance()
   local queries, result = analysed([[
local interface Choice
    function choose(self, value: string): string return value end
    function choose(self, value: integer): string
        coroutine.yield()
        return tostring(value)
    end
end

local record Concrete is Choice
    @override
    function choose(self, value: string): string return "local:" .. value end
end

local choice = new Concrete()
local text = choice:choose("ready")
local number = choice:choose(42)
return text, number
]])
   local calls = findMethods(result.root)
   assertEq(#calls, 2, "both concrete calls selected an entry")
   local text = queries.callee(calls[1])
   local number = queries.callee(calls[2])
   assert(text and number and text ~= number,
      "local and inherited entries retain distinct bodies")
   assertEq(text.summary.yields, false, "the override stays pure")
   assertEq(number.summary.yields, true,
      "the inherited overload retains its yield summary")
end

function test.aliasOfMergesTwoSpellingsOfOneTable()
   local queries, result = analysed([[
local xs: {integer} = {1, 2, 3}
local ys = xs
ys[1] = 9
return xs
]])
   local body = queries.body(result.root.blocks[1])
   local first = findName(result.root, "xs")
   local second = findName(result.root, "ys")
   assert(first and second, "both names are present")
   assertEq(body.aliasOf(first), body.aliasOf(second),
      "an alias shares its source's class")
   assert(body.aliasOf(first) ~= nil, "and the class is a real value")
end

function test.usesCountsEveryMention()
   local queries, result = analysed([[
local xs: {integer} = {1, 2, 3}
local a = xs
local b = xs
return a, b
]])
   local body = queries.body(result.root.blocks[1])
   local tok = findName(result.root, "xs")
   assertEq(body.uses(tok.definition), 3, "the binding and its two reads")
end

function test.shapeStableRefusesAWriteThroughAnAlias()
   local queries, result = analysed([[
local xs: {integer} = {1, 2, 3}
local ys = xs
ys[4] = 9
return xs
]])
   local block = result.root.blocks[1]
   local body = queries.body(block)
   local tok = findName(result.root, "xs")
   local ok, reason, related = body.shapeStable(block, body.aliasOf(tok))
   assertEq(ok, false, "a write through an alias changes the shape")
   assertEq(reason, "the array may change shape in the loop", "and says so")
   assert(related, "and points at the write")
end

function test.shapeStableAcceptsABodyThatOnlyReads()
   local queries, result = analysed([[
local xs: {integer} = {1, 2, 3}
local total = 0
total = total + xs[1]
return total
]])
   local block = result.root.blocks[1]
   local body = queries.body(block)
   local tok = findName(result.root, "xs")
   assertEq(body.shapeStable(block, body.aliasOf(tok)), true,
      "reading an element is not a shape change")
end

function test.shapeStableRefusesAnOpaqueCall()
   local queries, result = analysed([[
local xs: {integer} = {1, 2, 3}
print(xs)
return xs
]])
   local block = result.root.blocks[1]
   local body = queries.body(block)
   local tok = findName(result.root, "xs")
   local ok, reason = body.shapeStable(block, body.aliasOf(tok))
   assertEq(ok, false, "a call the summaries cannot see through stops the proof")
   assertEq(reason, "a call in the loop may mutate or expose the array", "and says so")
end

function test.insteadRedirectsTheWalkAtOneNode()
   -- What a loop needs to skip its own header. Without it the `ipairs` call in the
   -- iterator answers the question against the very array it is iterating.
   local queries, result = analysed([[
local xs: {integer} = {1, 2, 3}
local total = 0
for index, value in ipairs(xs) do
    total = total + value
end
return total
]])
   local block = result.root.blocks[1]
   local body = queries.body(block)
   local tok = findName(result.root, "xs")
   local loop = findKind(block, "forinStmt")
   assert(loop, "the loop is present")
   assertEq(body.shapeStable(block, body.aliasOf(tok)), false,
      "the iterator call is opaque when the walk reaches it")
   assertEq(body.shapeStable(block, body.aliasOf(tok),
      function(node) return node == loop and loop.body or nil end), true,
      "and the loop proves once its own header is stepped over")
end

function test.oneBodyIsPreparedOnce()
   local queries, result = analysed("local xs: {integer} = {1, 2, 3}\nreturn xs\n")
   local block = result.root.blocks[1]
   assertEq(queries.body(block), queries.body(block),
      "alias classes cost a walk, so the same body answers from the same table")
end

function test.noAnalysisMeansNoQueries()
   assertEq(analysis.queries(nil), nil, "nothing to ask")
   assertEq(analysis.queries({}), nil, "and a run that resolved nothing answers nothing")
end

-- `calledOnly` is the question lambda lifting asks: a nested function every mention
-- of which is a direct call can be lifted out with its captures passed instead. One
-- handed somewhere as a value cannot, whether or not it outlives the body.
local function calledOnly(inner, rest)
   local src = ("local function outer(t)\n   local function %s\n   %s\nend\nreturn outer\n")
      :format(inner, rest)
   local queries, result = analysed(src)
   local owner = findKind(result.root, "funcbody")
   local target = findKind(owner, "localFuncStmt")
   assert(target and target.name, "no nested function in the fixture")
   return queries.body(owner).calledOnly(target.name.definition)
end

function test.calledOnlyAcceptsACalleeAndNothingElse()
   assertEq(calledOnly("pick(x) return x end", "return pick(1) + pick(2)"), true,
      "every mention is a call")
   assertEq(calledOnly("pick(x) return x end", "return pick"), false, "returned")
   assertEq(calledOnly("pick(x) return x end", "return {pick}"), false, "stored")
   assertEq(calledOnly("cmp(a, b) return a < b end", "table.sort(t, cmp) return t"), false,
      "passed to something that will call it with an arity of its own")
   assertEq(calledOnly("pick(x) return x end", "table.sort(t, pick) return pick(1)"), false,
      "one value use is enough")
end

function test.calledOnlyCountsRecursionAsACall()
   assertEq(calledOnly("down(k) if k > 0 then return down(k - 1) end return 0 end",
      "return down(3)"), true, "a recursive call is a call")
end

function test.calledOnlyIgnoresTheDeclaringName()
   -- the name in `local function pick` binds rather than mentions, so a function
   -- declared and never called has no mentions at all and is not a candidate
   assertEq(calledOnly("pick(x) return x end", "return t"), false, "never called")
end

return test
