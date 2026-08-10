local ir = require("nupp.compiler.materialize.ir")
local providers = require("nupp.compiler.materialize.providers")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

function M.rendersADirectValueWithoutSourceFragments()
   local rendered, failure = ir.render({
      tag = "table",
      fields = {
         {name = "answer", value = {tag = "literal", value = 42}},
      },
   })
   assertEq(failure, nil, "valid IR renders")
   assertEq(rendered, "{answer=42}", "direct value")
end

function M.rendersAHygienicFactoryOnOneLine()
   local rendered, failure = ir.render({
      tag = "function",
      params = {1},
      body = {
         {tag = "let", id = 2, value = {
            tag = "field", object = {tag = "local", id = 1}, name = "build",
         }},
         {tag = "return", value = {
            tag = "call", callee = {tag = "local", id = 2},
            args = {{tag = "literal", value = 3}},
         }},
      },
   })
   assertEq(failure, nil, "factory IR renders")
   assertEq(rendered,
      "function(_nupp_m1) local _nupp_m2=(_nupp_m1).build;return (_nupp_m2)(3) end",
      "locals are renderer-owned")
   assertEq(rendered:find("\n", 1, true), nil, "the factory occupies one logical line")
end

function M.rejectsAnUndeclaredLocal()
   local _, failure = ir.render({tag = "local", id = 99})
   assert(failure and failure.message:find("undeclared", 1, true), failure and failure.message)
end

function M.rejectsRawSourceAndUnknownOperations()
   local _, failure = ir.render({tag = "source", text = "os.execute('no')"})
   assert(failure and failure.message:find("unknown", 1, true), failure and failure.message)
end

function M.rejectsAMalformedWorkerEnvelope()
   local expected = {}
   local _, failure = providers.lower({
      kind = "materialized",
      provider = "compiler-test",
      schema = 1,
      family = "Graph",
      fingerprint = "forged",
      payload = {values = {1}, nexts = {9}},
   }, expected, {globalTypes = {["nupp.__MaterializedTest"] = expected}})
   assertEq(failure.code, "NUPP2415", "worker data is validated before lowering")
end

return M
