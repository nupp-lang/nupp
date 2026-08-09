-- A record's inline method, run rather than read.
--
-- The receiver may be written out or left implicit, and both have to generate
-- the same function. Emitting a declared `self` beside the colon that already
-- binds one declared it twice: the inner name shadowed the receiver with the
-- first actual argument, which for `obj:m()` is nil, so every call crashed.
--
-- It checked clean in that state, which is why this suite runs the code. The
-- broken spelling was the one in the language reference's own worked example.
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

local function runs(src, label)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", env)
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

local function diagnostics(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local out = {}
   for _, diag in ipairs(check.check(result, "test.g.nupp", env)) do
      if diag.severity == "error" then
         out[#out + 1] = diag.code .. ":" .. diag.line
      end
   end
   return table.concat(out, " ")
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

function M.repeatedMethodNamesSelectDistinctBodies()
   local value, code = runs([[
local record Decoder
    function decode(text: string): string
        return "text:" .. text
    end

    function decode(value: integer): string
        return "integer:" .. tostring(value)
    end
end

local decoder = new Decoder {}
return decoder:decode("hello") .. "," .. decoder:decode(7)
]], "overloaded bodies")
   assertEq(value, "text:hello,integer:7", "each call reaches its selected body")
   assert(not code:find(":decode", 1, true),
      "the source method name must not dispatch at runtime")
   assert(code:find(":__nupp_m_", 1, true),
      "calls and bodies use hidden overload slots")
end

function M.anOverloadedReceiverIsEvaluatedOnce()
   local value = runs([[
local record Decoder
    function decode(text: string): string return text end
    function decode(value: integer): string return tostring(value) end
end
local calls = 0
local function decoder(): Decoder
    calls = calls + 1
    return new Decoder {}
end
return decoder():decode("once") .. ":" .. tostring(calls)
]], "overloaded receiver evaluation")
   assertEq(value, "once:1", "colon dispatch evaluates the receiver once")
end

function M.overloadedMethodsRequireAUniqueCall()
   local declaration = [[
local record Decoder
    function decode(text: string): string return text end
    function decode(value: integer): string return tostring(value) end
end
local decoder = new Decoder {}
]]
   assertEq(diagnostics(declaration .. "decoder:decode(true)"), "NUPP2125:6")
   assertEq(diagnostics(declaration .. "local value: any = 1\ndecoder:decode(value)"),
      "NUPP2126:7")
   assertEq(diagnostics(declaration .. "local held = decoder.decode"),
      "NUPP2126:6")
end

function M.returnTypesDoNotCreateMethodOverloads()
   assertEq(diagnostics([[
local record Bad
    function get(value: string): string return value end
    function get(value: string): integer return 1 end
end
]]), "NUPP2118:3")
end

function M.overloadedInterfaceDefaultsAreOverriddenPerEntry()
   local value = runs([[
local interface Decoder
    function decode(text: string): string return "default:" .. text end
    function decode(value: integer): string return "number:" .. tostring(value) end
end

local record LoudDecoder is Decoder
    @override
    function decode(text: string): string return "loud:" .. text end
end

local decoder: Decoder = new LoudDecoder {}
return decoder:decode("yes") .. "," .. decoder:decode(3)
]], "overloaded interface defaults")
   assertEq(value, "loud:yes,number:3",
      "one overload is replaced while the other default is inherited")
end

function M.separateInterfacesCanContributeOverloadEntries()
   local value = runs([[
local interface TextDecoder
    function decode(text: string): string return "text:" .. text end
end

local interface NumberDecoder
    function decode(value: integer): string return "number:" .. tostring(value) end
end

local record Decoder is TextDecoder, NumberDecoder
end

local decoder = new Decoder {}
return decoder:decode("yes") .. "," .. decoder:decode(3)
]], "distributed interface overloads")
   assertEq(value, "text:yes,number:3",
      "distinct inherited parameter packs become one overload group")
end

function M.bodylessInterfaceContractsUseTheSameSlots()
   local value = runs([[
local interface DecoderContract
    decode: function(self, string): string
        & function(self, integer): string
end

local record Decoder is DecoderContract
    function decode(text: string): string return "text:" .. text end
    function decode(value: integer): string return "number:" .. tostring(value) end
end

local decoder: DecoderContract = new Decoder {}
return decoder:decode("yes") .. "," .. decoder:decode(3)
]], "bodyless overloaded interface contract")
   assertEq(value, "text:yes,number:3",
      "interface calls and record bodies agree on signature slots")
end

function M.genericMethodEntriesKeepTheirDeclaredSlots()
   local value = runs([[
local record Codec<T>
    function encode(value: T): string return "one:" .. tostring(value) end
    function encode(values: {T}): string return "many:" .. tostring(values[1]) end
end

local codec: Codec<integer> = new Codec {}
return codec:encode(4) .. "," .. codec:encode({5})
]], "generic overloaded methods")
   assertEq(value, "one:4,many:5",
      "instantiation selects the declaration's stable runtime slot")
end

function M.safeNavigationKeepsOverloadSelection()
   local value = runs([[
local record Decoder
    function decode(text: string): string return text end
    function decode(value: integer): string return tostring(value) end
end
local decoder: Decoder? = nil
return decoder?.:decode("absent")
]], "safe overloaded method")
   assertEq(value, nil, "a nil receiver suppresses the selected hidden call")
end

function M.interfaceOverloadEntriesMustBeImplementedCompatibly()
   assertEq(diagnostics([[
local interface Contract
    decode: function(self, string): string
        & function(self, integer): string
end
local record Missing is Contract
    function decode(text: string): string return text end
end
]]), "NUPP2118:5")

   assertEq(diagnostics([[
local interface Contract
    function decode(text: string): string return text end
    function decode(value: integer): string return tostring(value) end
end
local record Wrong is Contract
    @override
    function decode(text: string): integer return 1 end
end
]]), "NUPP2118:7")
end

return M
