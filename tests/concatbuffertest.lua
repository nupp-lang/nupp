-- OPT-5, concat lowering. The property that matters is not that a buffer appears but
-- that the program still builds the same string, so every rewrite here is run and
-- compared against the same source compiled with the pass off.
local parser = require("nupp.compiler.parser")
local optimize = require("nupp.compiler.optimize")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function compile(src, level, dialect)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   check.check(result, "test.g.nupp", env)
   local remarks = optimize.run(result, {
      level = level,
      filename = "test.g.nupp",
      dialect = dialect or "luajit",
   })
   local code, diags = gen.generate(result, "test")
   assertEq(#diags, 0, "gen diagnostics for " .. src)
   return code, remarks
end

local function lowered(src)
   local code, remarks = compile(src, 1)
   local fired = false
   for _, entry in ipairs(remarks) do
      if entry.code == "OPT-5" then fired = true end
   end
   return fired, code
end

local function runCode(code, label, ...)
   local chunk, err = loadstring(code, "@concat_test")
   if not chunk then
      error(("%s: generated code does not load: %s\n---\n%s")
         :format(label, tostring(err), code), 2)
   end
   return chunk(...)
end

-- Rewritten, and still the same program: the buffer form is run beside the -O0 form
-- and both have to produce the same string.
local function assertLowered(src, ...)
   local fired, code = lowered(src)
   assertEq(fired, true, "expected OPT-5 to fire\n" .. src)
   assert(code:find("__nuppBuffer", 1, true), "the buffer is required\n" .. code)
   local plain = compile(src, 0)
   assertEq(runCode(code, "optimized", ...), runCode(plain, "plain", ...),
      "the rewrite changed the string it builds\n" .. code)
   return code
end

local function assertUntouched(src, why)
   local fired, code = lowered(src)
   assertEq(fired, false, (why or "expected OPT-5 to decline") .. "\n" .. src)
   assertEq(code:find("__nuppBuffer", 1, true), nil, "and no buffer is required")
end

local M = {}

function M.lowersAnAccumulatorBuiltRoundAForIn()
   local code = assertLowered([[
local items: {string} = {"a", "b", "c"}
local out = ""
for _, item in ipairs(items) do
    out = out .. item .. ","
end
return out
]])
   assert(code:find(":put(", 1, true), "appends rather than concatenates\n" .. code)
   assert(code:find(":tostring()", 1, true), "and finishes once\n" .. code)
end

function M.lowersANumericLoop()
   assertLowered([[
local out = ""
for i = 1, 4 do
    out = out .. i
end
return out
]])
end

function M.lowersAWhileLoop()
   assertLowered([[
local n = 0
local out = ""
while n < 3 do
    n = n + 1
    out = out .. n .. ";"
end
return out
]])
end

function M.lowersARepeatLoop()
   assertLowered([[
local n = 0
local out = ""
repeat
    n = n + 1
    out = out .. "x"
until n >= 3
return out
]])
end

function M.aLoopThatNeverRunsStillProducesTheEmptyString()
   -- The initialiser has to survive zero iterations, which is the whole reason the
   -- pass accepts only `""` for now.
   local code = assertLowered([[
local out = ""
for i = 1, 0 do
    out = out .. i
end
return out
]])
   assertEq(runCode(code, "empty"), "", "no iterations means no appends")
end

function M.keepsTheDeclarationSoLaterReadsSeeAString()
   -- The accumulator is still a local string after the loop; nothing downstream has
   -- to know a buffer was involved.
   local code = assertLowered([[
local out = ""
for i = 1, 3 do
    out = out .. i
end
return out .. "!" .. #out
]])
   assertEq(runCode(code, "later reads"), "123!3", "reads after the loop are ordinary")
end

function M.lineCountIsUnchanged()
   local src = [[
local out = ""
for i = 1, 3 do
    out = out .. i
end
return out
]]
   local code = assertLowered(src)
   local function lines(text)
      local n = 1
      for _ in text:gmatch("\n") do n = n + 1 end
      return n
   end
   assertEq(lines(code), lines(src), "attribution survives by the line count holding")
end

function M.readingTheAccumulatorInTheLoopDeclines()
   assertUntouched([[
local out = ""
for i = 1, 3 do
    out = out .. i
    if #out > 2 then break end
end
return out
]], "the half-built string is observed")
end

function M.assigningSomethingElseDeclines()
   assertUntouched([[
local out = ""
for i = 1, 3 do
    out = "reset"
end
return out
]], "that is not an accumulation")
end

function M.prependingDeclines()
   -- `out = i .. out` is not an append, and a buffer cannot do it.
   assertUntouched([[
local out = ""
for i = 1, 3 do
    out = i .. out
end
return out
]], "the accumulator is not the left operand")
end

function M.aCaptureInTheLoopDeclines()
   assertUntouched([[
local fns: {function(): string} = {}
local out = ""
for i = 1, 3 do
    out = out .. i
    fns[i] = function(): string return out end
end
return out
]], "a closure would see the buffer")
end

function M.touchingItBeforeTheLoopDeclines()
   assertUntouched([[
local out = ""
local seen = #out
for i = 1, 3 do
    out = out .. i
end
return out .. seen
]], "the binding is used before the accumulation starts")
end

function M.aNonEmptyInitialiserDeclines()
   assertUntouched([[
local out = "head"
for i = 1, 3 do
    out = out .. i
end
return out
]], "it would have to be seeded to survive zero iterations")
end

function M.straightLineConcatenationIsUntouched()
   -- Lua does a multi-operand concat in one operation, so this is already optimal and
   -- a buffer would cost more than it saves.
   assertUntouched([[
local a = "x"
local out = ""
out = out .. a .. a .. a
return out
]], "there is no loop")
end

function M.offAtLevelZero()
   local _, remarks = compile([[
local out = ""
for i = 1, 3 do
    out = out .. i
end
return out
]], 0)
   for _, entry in ipairs(remarks) do
      assertEq(entry.code ~= "OPT-5", true, "-O0 performs no rewrites")
   end
end

function M.lua51DialectSkipsThePass()
   local source = [[
local out = ""
for i = 1, 3 do
    out = out .. i
end
return out
]]
   local code, remarks = compile(source, 1, "lua51")
   for _, entry in ipairs(remarks) do
      assertEq(entry.code ~= "OPT-5", true, "Lua 5.1 cannot use string.buffer")
   end
   assertEq(code:find("__nuppBuffer", 1, true), nil,
      "Lua 5.1 output does not require LuaJIT's string.buffer")
end

function M.disablingThePassLeavesItAlone()
   local result = parser.parse([[
local out = ""
for i = 1, 3 do
    out = out .. i
end
return out
]], "test")
   check.check(result, "test.g.nupp", env)
   local remarks = optimize.run(result, {
      level = 1,
      filename = "test.g.nupp",
      disabled = {["OPT-5"] = true},
      dialect = "luajit",
   })
   for _, entry in ipairs(remarks) do
      assertEq(entry.code ~= "OPT-5", true, "-Zno-opt=OPT-5 turns it off")
   end
end

return M
