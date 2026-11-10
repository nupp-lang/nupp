local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local corepiece = require("nupp.compiler.vm.corepiece")
local corelink = require("nupp.compiler.vm.corelink")
local writer = require("nupp.compiler.vm.coreartifact")
local M = {}

local ALPHA = [[
module pieces.alpha
export function double(value: integer): integer return value * 2 end
export function triple(value: integer): integer return value * 3 end
export record Counter
    value: integer
    constructor(self, value: integer)
        self.value = value
    end
    function bump(self, by: integer): integer
        self.value = self.value + by
        return self.value
    end
end
]]

local BETA = [[
module pieces.beta
local alpha = require("pieces.alpha")
local function adder(n: integer): function(integer): integer
    return function(x: integer): integer return x + n end
end
export function sixfold(value: integer): integer
    local counter = alpha.Counter(value)
    counter:bump(1)
    return adder(0)(alpha.double(alpha.triple(counter.value - 1)))
end
]]

local MAIN = [[
module pieces.main
local alpha = require("pieces.alpha")
local beta = require("pieces.beta")
local function apply(f: function(integer): integer, value: integer): integer
    return f(value)
end
export const result = beta.sixfold(apply(alpha.double, 1))
]]

-- A program of `sources` ({name, text}), each checked in one environment that
-- holds those before it, its last the entry.
local function checkedProgram(sources, order)
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local declared = env.ensureProjectIndex(env).declaredModules
    local modules = {}
    for index, source in ipairs(sources) do
        local path = "=" .. source.name .. ".nupp"
        local parsed = parser.parse(source.text, path)
        test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
        local diagnostics, moduleType = checker.check(parsed, path, env, {
            moduleName = source.name,
            strict = false,
            lints = {["unused-binding"] = "off"}
        })
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= "error", diagnostic.msg)
        end
        declared[source.name] = true
        env.loaded[source.name] = {type = moduleType, exports = parsed.moduleExports}
        modules[index] = {name = source.name, path = path, parsed = parsed, diagnostics = diagnostics}
    end

    local described = modules
    if order then
        described = {}
        for index, at in ipairs(order) do
            described[index] = modules[at]
        end
    end

    return program.describe(described, sources[#sources].name)
end

local function sources(alpha)
    return {{name = "pieces.alpha", text = alpha or ALPHA}, {name = "pieces.beta", text = BETA}, {name = "pieces.main", text = MAIN}}
end

local function whole(alpha)
    return executable.fromChecked(program.compile(checkedProgram(sources(alpha)), tagged.forVersion(8)), 8)
end

local function pieces(alpha)
    return corepiece.compile(checkedProgram(sources(alpha)), tagged.forVersion(8))
end

-- Module alpha alone, as `text` spells it, as a piece.
local function alone(text)
    return corepiece.compile(checkedProgram({{name = "pieces.alpha", text = text}}), tagged.forVersion(8))[1]
end

-- Where `actual` first differs from `expected`, leaving out the semantic graphs
-- and contracts a linked executable keeps in its pieces.
local function difference(actual, expected, path)
    if type(actual) ~= type(expected) then
        return path .. ": " .. type(actual) .. " for " .. type(expected)
    elseif type(actual) ~= "table" then
        if actual == expected and (type(actual) ~= "number" or math.type(actual) == math.type(expected)) then
            return nil
        end
        return path .. ": " .. tostring(actual) .. " for " .. tostring(expected)
    end
    for key, item in pairs(expected) do
        if not (path == "semantic" and (key == "graphs" or key == "contracts")) then
            local found = difference(actual[key], item, path .. "." .. tostring(key))
            if found then
                return found
            end
        end
    end
    for key in pairs(actual) do
        if expected[key] == nil then
            return path .. "." .. tostring(key) .. ": unexpected"
        end
    end

    return nil
end

local function same(linked, expected)
    for _, key in ipairs({"version", "profile", "entry", "initializers", "functions", "instructionCount",
        "instanceCapacity", "instanceCreations", "frameDepth", "diagnostics"}) do
        local found = difference(linked[key], expected[key], key)
        assert(found == nil, found)
    end
    for _, key in ipairs({"schema", "entry", "modules", "catalog", "signatures"}) do
        local found = difference(linked.semantic[key], expected.semantic[key], "semantic." .. key)
        assert(found == nil, found)
    end
    test.eq(writer.encode(linked, {0}, 16, nil).bytes, writer.encode(expected, {0}, 16, nil).bytes)
end

local function refuses(action, message)
    local ok, problem = pcall(action)
    test.eq(ok, false)
    assert(tostring(problem):find(message, 1, true), tostring(problem))
end

function M.linkedProgramMatchesItsWholeProgramBuild()
    local built = pieces()
    local linked = corelink.link(built, "pieces.main")
    same(linked, whole())
    executable.validate(linked)
    -- It reaches across modules by symbols, and its closures by local ids.
    local named = {}
    for _, piece in ipairs(built) do
        for _, symbol in ipairs(piece.symbols) do
            named[symbol.kind] = (named[symbol.kind] or 0) + 1
        end
    end
    assert(named.module and named.module >= 2, "requires are module symbols")
    assert(named["function"] and named["function"] >= 1, "calls across modules are function symbols")
    assert(linked.diagnostics ~= nil, "a tail call keeps its program's call diagnostics")
end

function M.unchangedPiecesRelinkAfterAnEarlyModuleGainsAFunction()
    local before = pieces()
    local edited = ALPHA:gsub("^module pieces.alpha\n", "module pieces.alpha\nexport function zero(): integer return 0 end\n")
    local after = pieces(edited)
    -- The new function precedes every function of the later modules, so each
    -- of their owners moves; their pieces do not change.
    local relinked = corelink.link({after[1], before[2], before[3]}, "pieces.main")
    local expected = whole(edited)
    same(relinked, expected)
    same(corelink.link(after, "pieces.main"), expected)
end

function M.linkingHoldsSymbolsToTheirTargets()
    local before = pieces()
    local renamed = alone(ALPHA:gsub("bump", "raise"))
    local retyped = alone(ALPHA:gsub("function bump%(self, by: integer%): integer", "function bump(self, by: integer, more: integer): integer"))
    local function linked(first)
        return function()
            return corelink.link({first, before[2], before[3]}, "pieces.main")
        end
    end
    refuses(linked(renamed), "is missing")
    refuses(linked(retyped), "not the")
    refuses(function()
        return corelink.link({before[2], before[3]}, "pieces.main")
    end, "is not linked")
    refuses(function()
        return corelink.link({before[1], before[3], before[2]}, "pieces.main")
    end, "entry module must initialize last")
    refuses(function()
        return corelink.link({before[1], before[1], before[3]}, "pieces.main")
    end, "duplicate module")
end

function M.linkingHoldsWhatAPieceReadOfAnotherInitializer()
    local function compiled(flag)
        return corepiece.compile(checkedProgram({
            {name = "pieces.flag", text = flag},
            {name = "pieces.reader", text = "local flag = require(\"pieces.flag\")\nreturn flag"}
        }), tagged.forVersion(8))
    end
    local built = compiled("return true")
    test.eq(built[2].observed["pieces.flag"], "boolean")
    local changed = compiled("return 1")
    refuses(function()
        return corelink.link({changed[1], built[2]}, "pieces.reader")
    end, "was built reading pieces.flag as boolean")
    same(corelink.link(built, "pieces.reader"), executable.fromChecked(program.compile(checkedProgram({
        {name = "pieces.flag", text = "return true"},
        {name = "pieces.reader", text = "local flag = require(\"pieces.flag\")\nreturn flag"}
    }), tagged.forVersion(8)), 8))
end

-- A module that reads one later in the program reads its initializer result
-- as the whole program does: a function branching on a required number is
-- refused either way.
function M.piecesRefuseWhatTheWholeProgramRefuses()
    local sources = {
        {name = "pieces.flag", text = "return 1"},
        {name = "pieces.reader", text = "local function truth(): boolean\n    local value = require(\"pieces.flag\")\n    if value then\n        return true\n    end\n    return false\nend\nreturn truth"},
        {name = "pieces.main", text = "local truth = require(\"pieces.reader\")\nreturn truth()"}
    }
    local order = {2, 1, 3}
    local ok, problem = pcall(function()
        return executable.fromChecked(program.compile(checkedProgram(sources, order), tagged.forVersion(8)), 8)
    end)
    test.eq(ok, false)
    assert(tostring(problem):find("unsupported branch value", 1, true), tostring(problem))
    refuses(function()
        return corelink.link(corepiece.compile(checkedProgram(sources, order), tagged.forVersion(8)), "pieces.main")
    end, "unsupported branch value")
end

return M
