local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local sharedEnv = envMod.new(HERE)
local M = {}

local function diagnose(source)
    local result = parser.parse(source, "with-suspension.g.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    return check.check(result, "with-suspension.g.nupp", sharedEnv), result
end

local function runGenerated(source)
    local diagnostics, result = diagnose(source)
    for _, diagnostic in ipairs(diagnostics) do
        assert(
            diagnostic.severity == "warning" or diagnostic.severity == "note",
            diagnostic.code .. " " .. diagnostic.msg
        )
    end
    local code = gen.generate(result, "withsuspension")
    local chunk, problem = loadstring(code, "@with-suspension")
    assert(chunk, tostring(problem) .. "\n" .. code)

    return chunk()
end

local HANDLER = "local h = {park = function() end, canPark = function() return true end, shutdown = function() end}\n"

function M.ordinaryWithInstallsAndRestores()
    local before, inside, after = runGenerated(
        table.concat(
            {
                'local s = require("nupp.suspension")',
                HANDLER,
                "local before = s.handled()",
                "local inside = false",
                'with installation = require("nupp.suspension").install(h) do',
                "    inside = s.handled()",
                "end",
                "return before, inside, s.handled()",
            },
            "\n"
        )
    )
    assert(before == false and inside == true and after == false)
end

function M.ordinaryCallChecksTheHandler()
    local diagnostics = diagnose('with installation = require("nupp.suspension").install(42) do\nend')
    local found = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2006" and diagnostic.msg:find("Handler", 1, true) then
            found = true
        end
    end
    assert(found, "install must reject a non-handler")
end

function M.gotoCannotEnterInstallationScope()
    local diagnostics = diagnose(
        HANDLER .. table.concat(
            {"goto inside", 'with installation = require("nupp.suspension").install(h) do', "    ::inside::", "end",},
            "\n"
        )
    )
    local found = 0
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2602" then
            found = found + 1
        end
    end
    assert(found == 1, "one ownership diagnostic must reject entry without acquisition")
end

function M.returnDischargesInstallation()
    local value, beforeRelease, released = runGenerated(
        table.concat(
            {
                "local released = 0",
                "local h = {park = function() end, canPark = function() return true end,",
                "    shutdown = function() released = released + 1 end}",
                "local function run()",
                '    with installation = require("nupp.suspension").install(h) do',
                "        return 1, released",
                "    end",
                "end",
                "local answer, before = run()",
                "return answer, before, released",
            },
            "\n"
        )
    )
    assert(value == 1 and beforeRelease == 0 and released == 1)
end

function M.gotoOutDischargesInstallation()
    local answer, released = runGenerated(
        table.concat(
            {
                "local released = 0",
                "local h = {park = function() end, canPark = function() return true end,",
                "    shutdown = function() released = released + 1 end}",
                "local answer = 0",
                'with installation = require("nupp.suspension").install(h) do',
                "    answer = 1",
                "    goto done",
                "end",
                "answer = 2",
                "::done::",
                "return answer, released",
            },
            "\n"
        )
    )
    assert(answer == 1 and released == 1)
end

function M.nestedInstallationsRestoreTheOuterHandler()
    local outer, inner, restored, cleared = runGenerated(
        table.concat(
            {
                'local s = require("nupp.suspension")',
                HANDLER,
                "local outer, inner, restored",
                "with first = s.install(h) do",
                "    outer = s.handled()",
                "    with second = s.install(h) do",
                "        inner = s.handled()",
                "    end",
                "    restored = s.handled()",
                "end",
                "return outer, inner, restored, s.handled()",
            },
            "\n"
        )
    )
    assert(outer == true and inner == true and restored == true and cleared == false)
end

return M
