-- `nupp bc`: the bytecode a file compiles to, and what a loop cannot compile.
--
-- Driven through the real binary rather than the module, because the listing and the
-- exit status are the whole interface.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function project(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   for name, source in pairs(files) do
      local handle = assert(io.open(dir .. "/" .. name, "wb"))
      handle:write(source)
      handle:close()
   end
   return dir
end

-- LuaJIT's `popen` close answers only whether the pipe shut, never the exit status, so
-- the status is carried back through the pipe itself. `--check` is an exit status, so a
-- test that could not read one would not be testing it.
local function run(dir, argv)
   local pipe = assert(io.popen(
      ("cd %q && NO_COLOR= '%s' bc %s 2>&1; echo \"__exit__:$?\""):format(dir, NUPP, argv)))
   local out = pipe:read("*a")
   pipe:close()
   local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

   return (out:gsub("__exit__:%d+%s*$", "")), code
end

local SCALE = table.concat({
   "local function scale(values: {number}, by: number): number",
   "    local total = 0",
   "    for i = 1, #values do",
   "        total = total + values[i] * by",
   "    end",
   "    return total",
   "end",
   "",
   "return scale({1, 2, 3}, 2)",
   "",
}, "\n")

-- A closure reading the iteration. The `loop-invariant-closure` lint deliberately says
-- nothing about this one -- it cannot be lifted, so there is no edit to suggest -- but
-- the loop holding it still never compiles, which is the gap this closes.
local CAPTURING = table.concat({
   "local function each(items: {number}, fn: function(n: number): number): number",
   "    local total = 0",
   "    for i = 1, #items do",
   "        total = total + fn(items[i])",
   "    end",
   "    return total",
   "end",
   "",
   "local out = 0",
   "for round = 1, 4 do",
   "    out = out + each({1, 2}, function(n: number): number",
   "        return n * round",
   "    end)",
   "end",
   "return out",
   "",
}, "\n")

function M.theListingShowsSourceAgainstTheInstructionsItProduced()
   local dir = project{["demo.g.nupp"] = SCALE}
   local out, code = run(dir, "demo.g.nupp")
   test.equal(code, 0, out)
   assert(out:find("%d+ |%s+for i = 1, #values do"),
      "source lines are shown:\n" .. out)
   assert(out:find("FORI", 1, true) and out:find("FORL", 1, true),
      "the loop's bytecode is shown:\n" .. out)
   assert(out:find("-- function, lines 1-7", 1, true),
      "nested functions are listed with their own line span:\n" .. out)
end

-- The generated runtime preamble all lands on line 1, so a listing that showed it would
-- bury the file under something nobody wrote.
function M.theRuntimePreambleIsFoldedUnlessAskedFor()
   local dir = project{["demo.g.nupp"] = SCALE}
   local folded = run(dir, "demo.g.nupp")
   assert(folded:find("instructions of runtime preamble", 1, true),
      "the preamble is folded by default:\n" .. folded)
   assert(not folded:find("rawset", 1, true), "folded output still names the preamble")

   local shown = run(dir, "--prologue demo.g.nupp")
   assert(not shown:find("instructions of runtime preamble", 1, true),
      "--prologue stops folding:\n" .. shown)
   assert(shown:find("rawset", 1, true), "--prologue shows the preamble:\n" .. shown)
end

-- What the annotations cost, answered by the instructions rather than by a benchmark:
-- an indexed multiply-accumulate over a declared `{number}` is three instructions with
-- no call, no check and no boxing among them.
function M.declaredTypesLeaveNothingBehindInTheLoop()
   local dir = project{["demo.g.nupp"] = SCALE}
   local out = run(dir, "demo.g.nupp")
   local body = assert(out:match("total = total %+ values%[i%] %* by\n(.-)\n%s*%d+ |"),
      "the loop body's instructions:\n" .. out)
   assert(body:find("MULVV", 1, true) and body:find("ADDVV", 1, true),
      "the arithmetic is register ops:\n" .. body)
   assert(not body:find("CALL", 1, true), "the loop body calls nothing:\n" .. body)
end

function M.checkReportsALoopThatCannotCompileAndFailsForIt()
   local dir = project{["bad.g.nupp"] = CAPTURING}
   local out, code = run(dir, "--check bad.g.nupp")
   test.equal(code, 1, "a loop that cannot compile must fail --check:\n" .. out)
   assert(out:find("this loop never compiles: builds a function", 1, true),
      "the instruction is marked in place:\n" .. out)
   assert(out:find("in a loop that cannot compile", 1, true),
      "the run says how many:\n" .. out)
end

function M.checkPassesWhenEveryLoopCanCompile()
   local dir = project{["demo.g.nupp"] = SCALE}
   local out, code = run(dir, "--check demo.g.nupp")
   test.equal(code, 0, out)
   assert(not out:find("never compiles", 1, true), "nothing is marked:\n" .. out)
end

function M.jsonCarriesTheFindingAndItsCount()
   local dir = project{["bad.g.nupp"] = CAPTURING}
   local out, code = run(dir, "--format json bad.g.nupp")
   test.equal(code, 0, "json output alone does not fail; --check does\n" .. out)
   local decoded = require("cjson").decode(out)
   test.equal(decoded.file, "bad.g.nupp")
   assert(decoded.unrecordable >= 1, "the count is reported: " .. tostring(decoded.unrecordable))
   local found = false
   for _, fn in ipairs(decoded.functions) do
      for _, instruction in ipairs(fn.instructions) do
         if instruction.unrecordable then
            found = true
            assert(instruction.inLoop, "an unrecordable instruction is marked as in a loop")
            test.equal(instruction.op, instruction.op:upper())
         end
      end
   end
   assert(found, "json names the instruction, not only the count")
end

return M
