local parser = require("nupp.compiler.parser")
local check = require("fragment")
local annotations = require("nupp.compiler.annotations")

local function diagnostics(source)
    local parsed = parser.parse(source, "test.g.nupp")
    assert(#parsed.errors == 0, "invalid test source")
    local codes = {}
    for _, diagnostic in ipairs(check.check(parsed, "test.g.nupp")) do
        codes[#codes + 1] = diagnostic.code
    end

    return table.concat(codes, " ")
end

local suite = {}

function suite.interfaceWitnessesPreserveNominalCapabilities()
    local source = table.concat(
        {
            "local sealed interface Value end",
            "local record Managed is Value end",
            "local struct Native is Value x: number end",
            "local record Other end",
            "local witnesses: {Type<Value>} = {Managed, Native}",
        },
        "\n"
    )
    assert(diagnostics(source) == "")
    local function rejected(expression, label)
        assert(diagnostics(source .. "\n" .. expression):find("NUPP2001", 1, true), label)
    end

    rejected("local wrong: Type<Managed> = Native", "concrete witness mismatch")
    rejected("local wrong: Type<Value> = Other", "unclaimed interface")
    rejected("local wrong: Type<Value> = new Managed()", "managed instance is not a witness")
    rejected("local wrong: Type<Value> = new Native(0)", "native instance is not a witness")
end

function suite.annotationSourcesNormalizeEquivalentPaths()
    local registry = annotations.new()
    local function define(source)
        return registry:define({name = "ecsname", arguments = "none", targets = {"record"}, source = source,})
    end

    assert(define("src/example.nupp"))
    assert(define("./src/example.nupp"))
    local other, reason = define("other/example.nupp")
    assert(other == nil)
    assert(reason:find("already defined", 1, true), reason)
    registry:removeSource("src/./example.nupp")
    assert(registry:get("ecsname") == nil)
end

return suite
