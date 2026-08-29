local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local current = assert(io.popen("pwd"))
   HERE = current:read("*l") .. "/" .. HERE
   current:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

function M.theEvaluationHarnessIsImplementedAndTestedInNupp()
   local output = os.tmpname()
   local status = os.execute(("'%s' run tests/fixtures/evals_selftest.nupp > '%s' 2>&1")
      :format(NUPP, output))
   local file = assert(io.open(output, "rb"))
   local text = file:read("*a")
   file:close()
   os.remove(output)
   assert(status == 0, "the Nupp evaluation self-test failed: " .. text)
   assert(text:find("evaluation harness self-test passed", 1, true), text)
end

return M
