local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local sharedEnv = envMod.new(HERE)
local M = {}

local function diagnose(source)
    local result = parser.parse(source, "suspension-installation.nupp")
    assert(#result.errors == 0, result.errors[1] and result.errors[1].msg)
    return check.check(result, "suspension-installation.nupp", sharedEnv), result
end

local function runGenerated(source)
    local diagnostics, result = diagnose(source)
    for _, diagnostic in ipairs(diagnostics) do
        assert(
            diagnostic.severity == "warning" or diagnostic.severity == "note",
            diagnostic.code .. " " .. diagnostic.msg
        )
    end
    local code = gen.generate(result, "suspensioninstallation")
    local chunk, problem = loadstring(code, "@suspension-installation")
    assert(chunk, tostring(problem) .. "\n" .. code)

    return chunk()
end

local HANDLER = "local h = {park = function() end, canpark = function() return true end, shutdown = function() end}\n"

function M.anOrdinaryScopeInstallsAndRestores()
    local before, inside, after = runGenerated(
        table.concat(
            {
                'local s = require("coroutine.suspension")',
                'local host = require("coroutine.suspension.host")',
                HANDLER,
                "local before = s.handled()",
                "local inside = false",
                "do local installation = host.install(h) ;",
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
    local diagnostics = diagnose('do local installation = require("coroutine.suspension.host").install(42) ;\nend')
    local found = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2006" and diagnostic.msg:find("Handler", 1, true) then
            found = true
        end
    end
    assert(found, "install must reject a non-handler")
end

function M.returnDischargesInstallation()
    local value, beforeRelease, released = runGenerated(
        table.concat(
            {
                "local released = 0",
                "local h = {park = function() end, canpark = function() return true end,",
                "    shutdown = function() released = released + 1 end}",
                "local function run(): (integer, number)",
                '    do local installation = require("coroutine.suspension.host").install(h) ;',
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
                "local h = {park = function() end, canpark = function() return true end,",
                "    shutdown = function() released = released + 1 end}",
                "local answer = 0",
                'do local installation = require("coroutine.suspension.host").install(h) ;',
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

function M.breakDischargesInstallation()
    local released = runGenerated(
        table.concat(
            {
                "local released = 0",
                "local h = {park = function() end, canpark = function() return true end,",
                "    shutdown = function() released = released + 1 end}",
                "while true do",
                '    do local installation = require("coroutine.suspension.host").install(h) ;',
                "        break",
                "    end",
                "end",
                "return released",
            },
            "\n"
        )
    )
    assert(released == 1)
end

function M.errorDischargesInstallation()
    local ok, released = runGenerated(
        table.concat(
            {
                "local released = 0",
                "local h = {park = function() end, canpark = function() return true end,",
                "    shutdown = function() released = released + 1 end}",
                "local function run(): nil",
                '    do local installation = require("coroutine.suspension.host").install(h) ;',
                '        error("stop")',
                "    end",
                "end",
                "local ok = pcall(run)",
                "return ok, released",
            },
            "\n"
        )
    )
    assert(ok == false and released == 1)
end

function M.installationCarriesTheSuspensionRuntimeEffect()
    local diagnostics, result = diagnose(
        HANDLER .. 'do local installation = require("coroutine.suspension.host").install(h) ;\nend'
    )
    assert(#diagnostics == 0, diagnostics[1] and diagnostics[1].msg)
    assert(result.effects["runtime.suspension"], "the installation lost its runtime effect")
end

function M.nestedInstallationsRestoreTheOuterHandler()
    local outer, inner, restored, cleared = runGenerated(
        table.concat(
            {
                'local s = require("coroutine.suspension")',
                'local host = require("coroutine.suspension.host")',
                HANDLER,
                "local outer: boolean?, inner: boolean?, restored: boolean?",
                "do local first = host.install(h) ;",
                "    outer = s.handled()",
                "    do local second = host.install(h) ;",
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
