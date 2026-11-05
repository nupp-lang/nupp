local testAssert = require("assert")
-- A record's inline method, run rather than read.
--
-- A leading `self` makes an inline function an instance method. Without it the
-- function is static and is emitted on the declaration table with dot syntax.
local parser = require("nupp.compiler.syntax.parser")
local optimize = require("nupp.compiler.lua.optimize")
local gen = require("nupp.compiler.lua.gen")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function runs(src, label)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local diags = check.check(result, "test.nupp", env)
    for _, diag in ipairs(diags or {}) do
        if diag.severity == "error" then
            error(("%s: %s: %s\n%s"):format(label, diag.code, diag.msg, src), 2)
        end
    end
    optimize.run(result, {level = 1})
    local code, genDiags = gen.generate(result, "test")
    testAssert.eq(#genDiags, 0, "gen diagnostics")
    local chunk, err = loadstring(code, "@inline_method_test")
    if not chunk then
        error(("%s: generated code does not load: %s\n---\n%s"):format(label, tostring(err), code), 2)
    end
    local ok, value = pcall(chunk)
    if not ok then
        error(("%s: generated code raised: %s\n---\n%s"):format(label, tostring(value), code), 2)
    end

    return value, code
end

local function diagnostics(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local out = {}
    for _, diag in ipairs(check.check(result, "test.nupp", env)) do
        if diag.severity == "error" then
            out[#out + 1] = diag.code .. ":" .. diag.line
        end
    end

    return table.concat(out, " ")
end

local M = {}

function M.aWrittenOutReceiverWorks()
    -- The spelling `nupp reference` prints under Records.
    local value = runs(
        [[
local m = {}

record m.Point
    x: integer
    y: integer

    function lengthSquared(self): number
        return self.x * self.x + self.y * self.y
    end
end

return (m.Point(x = 3, y = 4)):lengthSquared()
]],
        "written-out self"
    )
    testAssert.eq(value, 25, "the receiver reaches the body")
end

function M.aReceiverlessFunctionIsStatic()
    local value = runs(
        [[
local m = {}

record m.Point
    function origin(): integer
        return 0
    end
end

return m.Point.origin()
]],
        "static function"
    )
    testAssert.eq(value, 0, "the declaration table carries the function")
end

function M.staticAndInstanceFunctionsGenerateDistinctForms()
    local value, code = runs(
        [[
local m = {}
record m.P
    n: integer
    function twice(self): number
        return self.n * 2
    end
    function answer(): number
        return 42
    end
end
return (m.P(n = 4)):twice() + m.P.answer()
]],
        "static and instance functions"
    )
    testAssert.eq(value, 50)
    assert(code:find("function m.P:twice()", 1, true))
    assert(code:find("function m.P.answer()", 1, true))
end

function M.parametersBesideTheReceiverSurvive()
    local value = runs(
        [[
local m = {}

record m.Adder
    base: integer

    function plus(self, a: integer, b: integer): number
        return self.base + a + b
    end
end

return (m.Adder(base = 1)):plus(2, 3)
]],
        "self plus parameters"
    )
    testAssert.eq(value, 6, "the arguments land on the right parameters")
end

function M.aFirstParameterNotCalledSelfIsAnOrdinaryParameter()
    -- Only a leading `self` is the receiver. Anything else keeps its place on a
    -- static function.
    local value = runs(
        [[
local m = {}

record m.Adder
    base: integer

    function plus(amount: integer): number
        return 10 + amount
    end
end

return m.Adder.plus(5)
]],
        "named first parameter"
    )
    testAssert.eq(value, 15, "the parameter remains the first argument")
end

function M.repeatedMethodNamesSelectDistinctBodies()
    local value, code = runs(
        [[
local record Decoder
    function decode(self, text: string): string
        return "text:" .. text
    end

    function decode(self, value: integer): string
        return "integer:" .. tostring(value)
    end
end
local decoder = Decoder()
return decoder:decode("hello") .. "," .. decoder:decode(7)
]],
        "overloaded bodies"
    )
    testAssert.eq(value, "text:hello,integer:7", "each call reaches its selected body")
    assert(not code:find(":decode", 1, true), "the source method name must not dispatch at runtime")
    assert(code:find(":__nupp_m_", 1, true), "calls and bodies use hidden overload slots")
end

function M.repeatedStaticNamesSelectDistinctBodies()
    local value, code = runs(
        [[
local record Decoder
    function decode(text: string): string return "text:" .. text end
    function decode(value: integer): string return "integer:" .. tostring(value) end
end
return Decoder.decode("hello") .. "," .. Decoder.decode(7)
]],
        "overloaded statics"
    )
    testAssert.eq(value, "text:hello,integer:7", "each static call reaches its selected body")
    assert(code:find("Decoder.__nupp_m_", 1, true), "static calls and bodies use hidden overload slots")
    testAssert.eq(
        diagnostics(
            [[
local record Decoder
    function decode(text: string): string return text end
    function decode(value: integer): string return tostring(value) end
end
local held = Decoder.decode
]]
        ),
        "NUPP2126:5"
    )
end

function M.anOverloadedReceiverIsEvaluatedOnce()
    local value = runs(
        [[
local record Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end
local calls = 0
local function decoder(): Decoder
    calls = calls + 1
    return Decoder()
end
return decoder():decode("once") .. ":" .. tostring(calls)
]],
        "overloaded receiver evaluation"
    )
    testAssert.eq(value, "once:1", "colon dispatch evaluates the receiver once")
end

function M.overloadedMethodsRequireAUniqueCall()
    local declaration = [[
local record Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end
local decoder = Decoder()
]]
    testAssert.eq(diagnostics(declaration .. "decoder:decode(true)"), "NUPP2125:6")
    testAssert.eq(diagnostics(declaration .. "local value: any = 1\ndecoder:decode(value)"), "NUPP2126:7")
    testAssert.eq(diagnostics(declaration .. "local held = decoder.decode"), "NUPP2126:6")
end

function M.returnTypesDoNotCreateMethodOverloads()
    testAssert.eq(
        diagnostics(
            [[
local record Bad
    function get(self, value: string): string return value end
    function get(self, value: string): integer return 1 end
end
]]
        ),
        "NUPP2118:3"
    )
end

function M.overloadedInterfaceDefaultsAreOverriddenPerEntry()
    local value = runs(
        [[
local interface Decoder
    function decode(self, text: string): string return "default:" .. text end
    function decode(self, value: integer): string return "number:" .. tostring(value) end
end

local record LoudDecoder is Decoder
    @override
    function decode(self, text: string): string return "loud:" .. text end
end

local decoder: Decoder = LoudDecoder()
return decoder:decode("yes") .. "," .. decoder:decode(3)
]],
        "overloaded interface defaults"
    )
    testAssert.eq(value, "loud:yes,number:3", "one overload is replaced while the other default is inherited")
end

function M.separateInterfacesCanContributeOverloadEntries()
    local value = runs(
        [[
local interface TextDecoder
    function decode(self, text: string): string return "text:" .. text end
end

local interface NumberDecoder
    function decode(self, value: integer): string return "number:" .. tostring(value) end
end

local record Decoder is TextDecoder, NumberDecoder
end

local decoder = Decoder()
return decoder:decode("yes") .. "," .. decoder:decode(3)
]],
        "distributed interface overloads"
    )
    testAssert.eq(value, "text:yes,number:3", "distinct inherited parameter packs become one overload group")
end

function M.bodylessInterfaceContractsUseTheSameSlots()
    local value = runs(
        [[
local interface DecoderContract
    decode: function(self, string): string
        & function(self, integer): string
end

local record Decoder is DecoderContract
    function decode(self, text: string): string return "text:" .. text end
    function decode(self, value: integer): string return "number:" .. tostring(value) end
end

local decoder: DecoderContract = Decoder()
return decoder:decode("yes") .. "," .. decoder:decode(3)
]],
        "bodyless overloaded interface contract"
    )
    testAssert.eq(value, "text:yes,number:3", "interface calls and record bodies agree on signature slots")
end

function M.explicitInterfaceLabelsStillSelectTheirMatchingImplementation()
    local value = runs(
        [[
local interface DecoderContract
    decode: function(self, text: string): string
        & function(self, value: string): string
end

local record Decoder is DecoderContract
    function decode(self, text: string): string return "text:" .. text end
    function decode(self, value: string): string return "value:" .. value end
end

local decoder: DecoderContract = Decoder()
return decoder:decode(text = "yes") .. "," .. decoder:decode(value = "yes")
]],
        "labeled bodyless interface contract"
    )
    testAssert.eq(value, "text:yes,value:yes", "explicit labels retain distinct inherited runtime slots")
end

function M.genericMethodEntriesKeepTheirDeclaredSlots()
    local value = runs(
        [[
local record Codec<T>
    function encode(self, value: T): string return "one:" .. tostring(value) end
    function encode(self, values: {T}): string return "many:" .. tostring(values[1]) end
end

local codec = Codec<integer>()
return codec:encode(4) .. "," .. codec:encode({5})
]],
        "generic overloaded methods"
    )
    testAssert.eq(value, "one:4,many:5", "instantiation selects the declaration's stable runtime slot")
end

function M.overloadsDistinguishGenericNominalsAndCallbackResults()
    local value = runs(
        [[
local record Box<T>
    value: T
end
local record Reader
    function read(self, box: Box<string>): string return "text:" .. box.value end
    function read(self, box: Box<integer>): string return "number:" .. tostring(box.value) end
    function call(self, callback: function(): string): string return callback() end
    function call(self, callback: function(): integer): string return tostring(callback()) end
end
local reader = Reader()
return reader:read(Box<string>(value = "yes"))
    .. "," .. reader:read(Box<integer>(value = 3))
    .. "," .. reader:call(function(): string return "done" end)
    .. "," .. reader:call(function(): integer return 4 end)
]],
        "generic nominal and callback result overloads"
    )
    testAssert.eq(value, "text:yes,number:3,done,4", "parameter type identities select distinct slots")
end

function M.safeNavigationKeepsOverloadSelection()
    local value = runs(
        [[
local record Decoder
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end
local decoder: Decoder? = nil
return decoder?.:decode("absent")
]],
        "safe overloaded method"
    )
    testAssert.eq(value, nil, "a nil receiver suppresses the selected hidden call")
end

function M.interfaceOverloadEntriesMustBeImplementedCompatibly()
    testAssert.eq(
        diagnostics(
            [[
local interface Contract
    decode: function(self, string): string
        & function(self, integer): string
end
local record Missing is Contract
    function decode(self, text: string): string return text end
end
]]
        ),
        "NUPP2118:5"
    )

    testAssert.eq(
        diagnostics(
            [[
local interface Contract
    function decode(self, text: string): string return text end
    function decode(self, value: integer): string return tostring(value) end
end
local record Wrong is Contract
    @override
    function decode(self, text: string): integer return 1 end
end
]]
        ),
        "NUPP2118:7"
    )
end

return M
