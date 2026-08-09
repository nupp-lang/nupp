-- The question surface `nupp.analysis` exposes, tested directly rather than through
-- the passes that ask. A pass declining is not evidence about which question said no,
-- and the whole reason these moved out of the provers is so that one answer serves
-- several callers -- which is only worth anything if the answer itself is pinned.
local parser = require("nupp.parser")
local check = require("nupp.check")
local envMod = require("nupp.env")
local analysis = require("nupp.analysis")
local cst = require("nupp.cst")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Parse, check, and hand back the query surface beside the tree.
local function analysed(src)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source")
   check.check(result, "test", envMod.new("."), {})
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

return test
