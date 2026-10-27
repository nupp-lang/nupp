local contract = require("nupp.compiler.vm.specializationcontract")
local specialization = require("nupp.runtime.vm.specialization")
local lower = require("nupp.compiler.clif.lower")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local M = {}

local function declaration(operation)
    return {
        annotations = {
            {name = "vmSpecialization", arguments = {{name = "operation", kind = "value", value = operation},}}
        }
    }
end

function M.ordinaryMeaningsDoNotChangeValuesOrRejectOutsideTheDomain()
    local value = {}
    assert(specialization.assertConstant(value) == value)
    assert(specialization.assertConstant(false) == false)
    for _, n in ipairs({-1000, -1, 0, 1, 1000}) do
        assert(specialization.specializeValue(n, -1, 1) == n)
        assert(specialization.pushContext(n) == nil)
        assert(specialization.popContext() == nil)
    end
    assert(specialization.inInterpreter() == true)
end

function M.semanticOperationsRequireExactCheckedMetadata()
    for _, name in ipairs({"assertConstant", "specializeValue", "pushContext", "popContext", "inInterpreter"}) do
        assert(contract.read(declaration(name), name) == name)
    end
    local duplicate = declaration("inInterpreter")
    duplicate.annotations[2] = duplicate.annotations[1]
    local unknownField = declaration("inInterpreter")
    unknownField.annotations[1].arguments[1].name = "hidden"
    local nonliteral = declaration("inInterpreter")
    nonliteral.annotations[1].arguments[1].kind = "type"
    for _, value in ipairs({
        {},
        duplicate,
        unknownField,
        nonliteral,
        declaration("unknown"),
        declaration("pushContext")
    }) do
        assert(not pcall(contract.read, value, "inInterpreter"))
    end
end

function M.variantDomainsHandleBothInt64EndsWithoutOverflow()
    for _, case in ipairs({
        {"0", "0", 1, 1},
        {"-0", "000", 1, 1},
        {"-2", "2", 5, 5},
        {"-10", "-8", 3, 3},
        {"999999999999999999", "1000000000000000000", 2, 2},
        {"-1000000000000000000", "-999999999999999999", 2, 2},
        {"9223372036854775805", "9223372036854775807", 3, 3},
        {"-9223372036854775808", "-9223372036854775806", 3, 3},
        {"0", "4095", 4096, 4096},
    }) do
        assert(contract.domain(case[1], case[2], case[3]) == case[4])
    end
    for _, case in ipairs({
        {"1", "0", 2},
        {"-8", "-10", 3},
        {"0", "0", 0},
        {"0", "0", 4097},
        {"0", "0", 1.5},
        {"-2", "2", 4},
        {"0", "4096", 4096},
        {"-9223372036854775808", "9223372036854775807", 4096},
        {"9223372036854775807", "9223372036854775808", 2},
        {"-9223372036854775809", "-9223372036854775808", 2},
        {"0x0", "1", 2},
        {"1.0", "2", 2},
        {"0", "nan", 2},
    }) do
        assert(not pcall(contract.domain, case[1], case[2], case[3]), table.concat(case, ","))
    end
end

function M.functionContractsSurviveCheckingAndExportLookup()
    local path = ROOT .. "/tests/specialization-use.nupp"
    local parsed = parser.parse(
        [[
const specialization = require("nupp.runtime.vm.specialization")
local result = specialization.inInterpreter()
assert(result)
]],
        path
    )
    local env = environment.new(ROOT, {cache = false, config = {include = {"src"}}})
    local diagnostics = checker.check(parsed, path, env, {})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity and diagnostic.severity ~= "error", diagnostic.msg)
    end
    local call = parsed.root.blocks[1].stats[2].exprs[1]
    assert(contract.read(call.obj.name.definition, "inInterpreter") == "inInterpreter")
end

function M.directLoweringUsesOrdinaryMeaningsAndTheConfiguredVariantBudget()
    local paths = {ROOT .. "/tests/fixtures/native/specialization.nupp"}
    local clif = lower.compile(ROOT, paths, {include = {"src"}, specializationVariantCap = 3})
    for _, name in ipairs({"identity", "bounded", "context", "interpreter"}) do
        assert(clif:find("function %" .. name, 1, true), name)
    end
    for _, name in ipairs({"assertConstant", "specializeValue", "pushContext", "popContext", "inInterpreter"}) do
        assert(not clif:find("%" .. name, 1, true), "ordinary intrinsic emitted a foreign call: " .. name)
    end
    local ok, problem = pcall(lower.compile, ROOT, paths, {include = {"src"}, specializationVariantCap = 2})
    assert(not ok and tostring(problem):find("exceeds variant cap", 1, true), tostring(problem))
    for _, cap in ipairs({0, 1.5, 4097, false}) do
        assert(not pcall(lower.compile, ROOT, paths, {include = {"src"}, specializationVariantCap = cap}))
    end
end

return M
