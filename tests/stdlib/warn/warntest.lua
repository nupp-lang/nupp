local test = require("assert")
local providerstate = require("helpers.providerstate")
local M = {}

local function fixture()
    local calls = {}
    local load = providerstate.instance({warn = true}, {
        ["debug.log"] = {
            formodule = function(name)
                test.eq(name, "warn")
                return {
                    emit = function(level, line, message)
                        calls[#calls + 1] = {level, line, message}
                    end
                }
            end
        },
    })

    return load("warn"), calls
end

function M.startsEnabledAndConcatenatesWithoutFormatting()
    local warn, calls = fixture()
    warn("a", "%s", "b")
    test.eq(#calls, 1)
    test.eq(calls[1][1], 2)
    test.eq(calls[1][2], 0)
    test.eq(calls[1][3], "a%sb")
end

function M.singleControlStringsToggleWarnings()
    local warn, calls = fixture()
    warn("@off")
    warn("hidden")
    warn("@unknown")
    test.eq(#calls, 0)
    warn("@on")
    warn("shown")
    warn("@off", " remains a message")
    test.eq(#calls, 2)
    test.eq(calls[1][3], "shown")
    test.eq(calls[2][3], "@off remains a message")
end

function M.validatesEveryArgumentEvenWhenDisabled()
    local warn, calls = fixture()
    warn("@off")
    for _, args in ipairs({{n = 0}, {n = 1, false}, {n = 2, "a", false}, {n = 3, "a", nil, "b"}}) do
        test.eq(pcall(warn, unpack(args, 1, args.n)), false)
    end
    warn("@on")
    warn(12, ":", 3)
    test.eq(calls[1][3], "12:3")
end

function M.usesTheApplicationSinkIndependentlyOfItsLevelFilter()
    local log = require("debug.log")
    local warning = require("warn")
    local messages = {}
    local previousLevel = log.setlevel("off")
    local previousSink = log.setsink(function(level, module, line, message)
        messages[#messages + 1] = {level, module, line, message}
    end)
    local ok, reason = pcall(function()
        warning("@on")
        warning("shared ", "sink")
        test.eq(#messages, 1)
        test.eq(messages[1][1], 2)
        test.eq(messages[1][2], "warn")
        test.eq(messages[1][3], 0)
        test.eq(messages[1][4], "shared sink")
        warning("@off")
        warning("hidden")
        test.eq(#messages, 1)
    end)
    warning("@on")
    log.setsink(previousSink)
    log.setlevel(previousLevel)
    assert(ok, reason)
end

function M.checkedGlobalAndRequireShareOneFunction()
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local gen = require("nupp.compiler.lua.gen")
    local root = require("helpers.paths").tests .. "/.."
    local env = require("nupp.compiler.project.env").new(root)
    local source = 'local direct = warn\nlocal imported = require("warn")\nreturn direct == imported'
    local parsed = parser.parse(source, "warning-identity.nupp")
    test.eq(#parsed.errors, 0)
    local diagnostics = checker.check(parsed, "warning-identity.nupp", env)
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local code, generated = gen.generate(parsed, "warning-identity.nupp")
    test.eq(#generated, 0)
    assert(code:find('require("warn")', 1, true), "the builtin resolves the public warning module")
    test.eq(assert(loadstring(code))(), true)

    local shadowed = parser.parse(
        'local warn = function(message: string): string return message end\nreturn warn("local")',
        "warning-shadow.nupp"
    )
    test.eq(#checker.check(shadowed, "warning-shadow.nupp", env), 0)
    local ordinary = gen.generate(shadowed, "warning-shadow.nupp")
    test.eq(ordinary:find('require("warn")', 1, true), nil)
    test.eq(assert(loadstring(ordinary))(), "local")
end

return M
