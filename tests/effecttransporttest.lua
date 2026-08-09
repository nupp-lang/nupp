-- S0: the suspension effect, transported across a module boundary.
--
-- The fact rides on the function type rather than beside it, so an alias carries it
-- without anything having to look up where the value came from. That is only possible
-- because boundary finalization qualifies each exported callable from its own
-- definition: interning collapses two same-signature exports into one type, and the
-- module shape alone has already lost which of them yields.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local T = require("nupp.compiler.types")
local relations = require("nupp.compiler.relations")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

-- Checks a source against an environment rooted where the fixtures live, so a
-- `require` in it resolves to `tests/fixtures`.
local function moduleTypeOf(src, name)
   local env = envMod.new(HERE)
   local result = parser.parse(src, (name or "test") .. ".g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags, moduleType = check.check(result, (name or "test") .. ".g.nupp", env)
   for _, diag in ipairs(diags) do
      if diag.severity ~= "warning" and diag.severity ~= "note" then
         error(("unexpected %s: %s"):format(diag.code, diag.msg), 2)
      end
   end
   return moduleType, result
end

local function fieldType(moduleType, name)
   for _, field in ipairs(moduleType and moduleType.fields or {}) do
      if field.name == name then
         return field.read or field.type
      end
   end
   return nil
end

-- The type a local binding ended up with, found by name in the checked tree.
local function localType(result, name)
   local found
   local cst = require("nupp.compiler.cst")
   local function walk(node)
      if not node or cst.isToken(node) or found then return end
      if node.kind == "localStmt" then
         for index, tok in ipairs(node.names or {}) do
            if tok.text == name then
               local expr = (node.exprs or {})[index]
               found = expr and expr.resolvedType
            end
         end
      end
      for _, child in ipairs(node) do walk(child) end
   end
   walk(result.root)
   return found
end

local FIXTURE = 'local B = require("fixtures.effects")\n'

local M = {}

function M.sameSignatureExportsGetDistinctTypes()
   -- The trap this whole mechanism exists for. Both are `function(): nil`, so before
   -- finalization they are one interned type and one of them is wrong.
   local moduleType = moduleTypeOf(FIXTURE .. "return B", "consumer")
   local exported = moduleTypeOf(io.open(HERE .. "/fixtures/effects.nupp"):read("*a"),
      "fixtures/effects")
   local safe, waits = fieldType(exported, "safe"), fieldType(exported, "waits")
   assertTrue(safe ~= nil and waits ~= nil, "both exports are present")
   assertEq(safe.tag, "func", "safe is callable")
   assertEq(waits.tag, "func", "waits is callable")
   assertTrue(safe ~= waits,
      "identical signatures must not share one type when only one yields")
   assertEq(safe.noYield, true, "safe cannot suspend")
   assertEq(waits.noYield, nil, "waits may suspend")
   assertTrue(moduleType ~= nil, "the consumer checks")
end

function M.anAliasOfANonYieldingExportStaysNonYielding()
   local _, result = moduleTypeOf(FIXTURE .. "local f = B.safe\nreturn f", "consumer")
   local t = localType(result, "f")
   assertTrue(t ~= nil and t.tag == "func", "the alias is callable")
   assertEq(t.noYield, true, "the guarantee rides on the type, not on the name")
end

function M.anAliasOfAYieldingExportStaysYielding()
   local _, result = moduleTypeOf(FIXTURE .. "local f = B.waits\nreturn f", "consumer")
   local t = localType(result, "f")
   assertTrue(t ~= nil and t.tag == "func", "the alias is callable")
   assertEq(t.noYield, nil, "a may-yield export does not become safe by being renamed")
end

function M.nestedExportedTablesAnswerPerLeaf()
   local exported = moduleTypeOf(io.open(HERE .. "/fixtures/effects.nupp"):read("*a"),
      "fixtures/effects")
   local ops = fieldType(exported, "ops")
   assertTrue(ops ~= nil and ops.tag == "shape", "ops is a table of callables")
   local byName = {}
   for _, field in ipairs(ops.fields or {}) do
      byName[field.name] = field.read or field.type
   end
   assertEq(byName.reader and byName.reader.noYield, true, "the non-yielding leaf")
   assertEq(byName.waiter and byName.waiter.noYield, nil, "the yielding leaf")
end

function M.aCallbackParameterIsNotStampedWithItsOwnersEffect()
   -- `withCallback` cannot suspend, but the function it takes is somebody else's
   -- value and nothing here has seen its definition.
   local exported = moduleTypeOf(io.open(HERE .. "/fixtures/effects.nupp"):read("*a"),
      "fixtures/effects")
   local outer = fieldType(exported, "withCallback")
   assertTrue(outer ~= nil and outer.tag == "func", "the export is callable")
   local param = (outer.params or {})[1]
   assertTrue(param ~= nil and param.tag == "func", "its parameter is callable")
   assertEq(param.noYield, nil,
      "a parameter is a separate callable and stays conservatively may-yield")
end

function M.anUncontractedBodylessFunctionMayYield()
   -- Nothing established a guarantee, so there is not one. The qualifier is positive
   -- for exactly this reason: silence is may-yield.
   local moduleType = moduleTypeOf(
      "local M = {}\nfunction M.f(): nil\n    someUnknownGlobal()\nend\nreturn M")
   local t = fieldType(moduleType, "f")
   assertTrue(t ~= nil, "the export is present")
   assertEq(t.noYield, nil, "an unknowable body may suspend")
end

function M.anEffectsContractSuppliesTheNegativeFact()
   local moduleType = moduleTypeOf(table.concat({
      "local M = {}",
      "@effects(yields = false)",
      "function M.f(): nil",
      "end",
      "return M",
   }, "\n"))
   local t = fieldType(moduleType, "f")
   assertTrue(t ~= nil, "the export is present")
   assertEq(t.noYield, true, "a declared contract establishes the guarantee")
end

function M.aNonYieldingFunctionSatisfiesAMayYieldSlot()
   local safe = T.withYields(T.func({}, {T.nil_}), false)
   local any = T.func({}, {T.nil_})
   assertTrue(relations.isA(safe, any),
      "a guarantee only has to hold where one was asked for")
end

function M.aMayYieldFunctionDoesNotSatisfyANoYieldSlot()
   local safe = T.withYields(T.func({}, {T.nil_}), false)
   local any = T.func({}, {T.nil_})
   local ok, why = relations.isA(any, safe)
   assertEq(ok, false, "a may-yield function cannot fill a slot that forbids it")
   assertTrue(tostring(why):find("suspend", 1, true) ~= nil,
      "the refusal says why: " .. tostring(why))
end

function M.theQualifierReachesBothIdentityMechanisms()
   -- Incremental cutoff compares interned identity; persistent build reuse compares
   -- the fingerprint. A change visible to only one of them is a stale artifact.
   local safe = T.withYields(T.func({}, {T.nil_}), false)
   local any = T.func({}, {T.nil_})
   assertTrue(safe ~= any, "interned identity separates them")
   assertTrue(safe.id ~= any.id, "and so do their keys")

   -- Unconditional on purpose. Guarding this behind "if the export exists" would let
   -- the assertion quietly stop running the day the export moves, which is the one
   -- circumstance under which it matters.
   local modules = require("nupp.compiler.build.modules")
   assertTrue(modules.typeFingerprint ~= nil,
      "build reuse hashes the boundary through this")
   assertTrue(modules.typeFingerprint(safe) ~= modules.typeFingerprint(any),
      "the build fingerprint separates them too")
end

function M.aNominalMethodIsOutsideTheQualifiedBoundary()
   -- Scope decision, and observable rather than asserted. A method declared on a
   -- record is not a module field, so finalization never sees it and its type keeps
   -- no guarantee. That is deliberate: a nominal's identity survives rechecks and
   -- `typeFingerprint` does not expand its members, so a method body that started
   -- yielding could not invalidate a dependent through the type. Claiming a guarantee
   -- that cannot be invalidated is the one thing worse than claiming none.
   local moduleType = moduleTypeOf(table.concat({
      "local M = {}",
      "record M.Thing",
      "    n: integer",
      "end",
      "function M.Thing:quiet(): nil",
      "end",
      "function M.plain(): nil",
      "end",
      "return M",
   }, "\n"))
   assertEq(fieldType(moduleType, "quiet"), nil,
      "a method is not a module field")
   local plain = fieldType(moduleType, "plain")
   assertTrue(plain ~= nil and plain.tag == "func", "a plain export still is one")
   assertEq(plain.noYield, true,
      "and it is qualified, so the boundary is where it says it is")
end

function M.withYieldsPreservesEverythingElse()
   -- The clone exists so finalization does not respell `T.func`'s argument list and
   -- silently drop whatever is added to it next.
   local original = T.func(
      {T.string}, {T.integer}, true, {"plain"}, nil, nil, nil, nil, nil, nil, nil,
      T.string, nil, nil, nil, nil, nil, nil)
   local qualified = T.withYields(original, false)
   assertEq(qualified.noYield, true, "the qualifier is set")
   assertEq(#qualified.params, #original.params, "parameters survive")
   assertEq(qualified.params[1], original.params[1], "and are the same types")
   assertEq(qualified.rets[1], original.rets[1], "results survive")
   assertEq(qualified.vararg, original.vararg, "the vararg flag survives")
   assertEq(qualified.varargType, original.varargType, "the vararg type survives")
   assertEq(qualified.paramModes[1], original.paramModes[1], "ownership modes survive")
   assertEq(T.withYields(qualified, false), qualified,
      "setting what is already set answers the same type")
end

function M.qualifyingIsIdempotent()
   local exported = moduleTypeOf(io.open(HERE .. "/fixtures/effects.nupp"):read("*a"),
      "fixtures/effects")
   local again = moduleTypeOf(io.open(HERE .. "/fixtures/effects.nupp"):read("*a"),
      "fixtures/effects")
   assertEq(fieldType(exported, "safe"), fieldType(again, "safe"),
      "two checks of one source agree, so the interface hash is stable")
   assertEq(exported, again, "and so does the whole boundary")
end

-- Two edits to one dependency, one of which changes the boundary and one of which
-- does not. What separates them is the effect, not the signature: both versions of
-- `waiter` are `function(): nil`.
local function withProject(depSource, run)
   local query = require("nupp.compiler.query")
   local incremental = require("nupp.compiler.incremental")
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local function write(path, text)
      local f = assert(io.open(path, "w"))
      f:write(text)
      f:close()
   end
   local depPath, mainPath = dir .. "/dep.g.nupp", dir .. "/main.g.nupp"
   write(depPath, depSource)
   write(mainPath, table.concat({
      "local dep = require('dep')",
      "local f = dep.waiter",
      "return f",
   }, "\n"))
   local inc = incremental.new(dir)
   local ok, err = pcall(run, inc, depPath, mainPath, write)
   os.execute("rm -rf '" .. dir .. "'")
   if not ok then error(err, 0) end
end

local QUIET = table.concat({
   "local M = {}",
   "function M.waiter(): nil",
   "    local n = 1",
   "end",
   "return M",
}, "\n")

function M.aBodyThatStartsYieldingInvalidatesDependents()
   withProject(QUIET, function(inc, depPath, mainPath)
      inc.checkFile(mainPath)
      local cold = inc.q.stats.checkModule
      -- Same signature, same everything the eye sees. The boundary changed anyway.
      inc.changeDocument(depPath, (QUIET:gsub("local n = 1", "coroutine.yield()")))
      inc.checkFile(mainPath)
      assertEq(inc.q.stats.checkModule, cold + 2,
         "dep AND main recheck: the export stopped being non-yielding")
   end)
end

function M.aBodyEditThatKeepsTheEffectDoesNot()
   withProject(QUIET, function(inc, depPath, mainPath)
      inc.checkFile(mainPath)
      local cold = inc.q.stats.checkModule
      inc.changeDocument(depPath, (QUIET:gsub("local n = 1", "local n = 2")))
      inc.checkFile(mainPath)
      assertEq(inc.q.stats.checkModule, cold + 1,
         "only dep rechecks: the boundary is unchanged, so cutoff holds")
   end)
end

return M
