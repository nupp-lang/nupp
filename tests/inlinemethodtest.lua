-- A record's inline method, run rather than read.
--
-- The receiver may be written out or left implicit, and both have to generate
-- the same function. Emitting a declared `self` beside the colon that already
-- binds one declared it twice: the inner name shadowed the receiver with the
-- first actual argument, which for `obj:m()` is nil, so every call crashed.
--
-- It checked clean in that state, which is why this suite runs the code. The
-- broken spelling was the one in the language reference's own worked example.
local parser = require("nupp.parser")
local optimize = require("nupp.optimize")
local gen = require("nupp.gen")
local check = require("fragment")
local envMod = require("nupp.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function runs(src, label)
   local result = parser.parse(src, "test")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test", env)
   for _, diag in ipairs(diags or {}) do
      if diag.severity == "error" then
         error(("%s: %s: %s\n%s"):format(label, diag.code, diag.msg, src), 2)
      end
   end
   optimize.run(result, {level = 1})
   local code, genDiags = gen.generate(result, "test")
   assertEq(#genDiags, 0, "gen diagnostics")
   local chunk, err = loadstring(code, "@inline_method_test")
   if not chunk then
      error(("%s: generated code does not load: %s\n---\n%s")
         :format(label, tostring(err), code), 2)
   end
   local ok, value = pcall(chunk)
   if not ok then
      error(("%s: generated code raised: %s\n---\n%s")
         :format(label, tostring(value), code), 2)
   end
   return value, code
end

local M = {}

function M.aWrittenOutReceiverWorks()
   -- The spelling `nupp reference` prints under Records.
   local value = runs([[
local m = {}

record m.Point
    x: integer
    y: integer

    function lengthSquared(self): number
        return self.x * self.x + self.y * self.y
    end
end

return (new m.Point {x = 3, y = 4}):lengthSquared()
]], "written-out self")
   assertEq(value, 25, "the receiver reaches the body")
end

function M.animplicitReceiverWorks()
   local value = runs([[
local m = {}

record m.Point
    x: integer
    y: integer

    function lengthSquared(): number
        return self.x * self.x + self.y * self.y
    end
end

return (new m.Point {x = 3, y = 4}):lengthSquared()
]], "implicit self")
   assertEq(value, 25, "the receiver reaches the body")
end

function M.bothSpellingsGenerateTheSameFunction()
   local _, written = runs([[
local m = {}
record m.P
    n: integer
    function twice(self): number
        return self.n * 2
    end
end
return (new m.P {n = 4}):twice()
]], "written-out self")
   local _, implicit = runs([[
local m = {}
record m.P
    n: integer
    function twice(): number
        return self.n * 2
    end
end
return (new m.P {n = 4}):twice()
]], "implicit self")
   assertEq(written:match("function m%.P:twice%b()"),
      implicit:match("function m%.P:twice%b()"),
      "the receiver is not declared twice in one and once in the other")
end

function M.parametersBesideTheReceiverSurvive()
   local value = runs([[
local m = {}

record m.Adder
    base: integer

    function plus(self, a: integer, b: integer): number
        return self.base + a + b
    end
end

return (new m.Adder {base = 1}):plus(2, 3)
]], "self plus parameters")
   assertEq(value, 6, "the arguments land on the right parameters")
end

function M.aFirstParameterNotCalledSelfIsAnOrdinaryParameter()
   -- Only a leading `self` is the receiver. Anything else keeps its place, and
   -- the implicit receiver is still available under its own name.
   local value = runs([[
local m = {}

record m.Adder
    base: integer

    function plus(amount: integer): number
        return self.base + amount
    end
end

return (new m.Adder {base = 10}):plus(5)
]], "named first parameter")
   assertEq(value, 15, "the argument does not land on the receiver")
end

return M
