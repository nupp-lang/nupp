local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local program = require("program")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local stdlib = require("nupp.compiler.stdlib")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

-- Check, then lower under the module name a logged line should carry.
local function checked(src, moduleName)
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors in test source")
    local diags = check.check(result, "test.nupp", env)
    testAssert.equal(#diags, 0, diags[1] and diags[1].msg or "check diagnostics")
    result.moduleName = moduleName or "test"

    return result
end

-- The VM image a module lowers to.
local function compile(src, moduleName)
    return program.image(checked(src, moduleName), moduleName or "test")
end

local function run(src, moduleName)
    return program.run(checked(src, moduleName), moduleName or "test")
end

local function codesOf(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.equal(#result.errors, 0, "syntax errors in test source")
    local out = {}
    for _, d in ipairs(check.check(result, "test.nupp", env)) do
        out[#out + 1] = d.code
    end

    return table.concat(out, " ")
end

-- The logging module itself, so behaviour can be exercised without generating a
-- module around it. It is an ordinary module now, not something a bootstrap installs.
local function runtime()
    return require("nupp.log")
end

-- A sink that records what it was handed, so a test can read the parts rather
-- than parse a rendered line back apart.
local function recorder()
    local lines = {}
    return lines, function(level, module, line, message)
        lines[#lines + 1] = {level = level, module = module, line = line, message = message}
    end
end

local M = {}

function M.formatDirectivesAreCheckedAtTheCallSite()
    testAssert.equal(codesOf("nupp.log.error('id %d', 3)"), "", "a well-formed call is clean")
    testAssert.equal(codesOf("nupp.log.error('id %d')"), "NUPP2006", "a directive with no argument is reported")
    testAssert.equal(codesOf("nupp.log.info('%s and %d', 'a', 'b')"), "NUPP2006", "an argument of the wrong type is reported")
    testAssert.equal(codesOf("nupp.log.debug('plain')"), "", "a format with no directives is clean")
    testAssert.equal(
        codesOf(
            table.concat(
                {"@derive(nupp.derive.Debug)", "local record Value end", "nupp.log.debug('value=%?', new Value())",},
                "\n"
            )
        ),
        "",
        "a debug directive accepts nupp.Debug"
    )
    testAssert.equal(codesOf("nupp.log.debug('value=%?', 'wrong')"), "NUPP2006", "a debug directive requires nupp.Debug")
    testAssert.equal(
        codesOf(table.concat({"local logger = nupp.log.named('named')", "logger:debug('value=%?', 'wrong')",}, "\n")),
        "NUPP2006",
        "a named logger requires the same contract"
    )
end

function M.levelNamesAreCheckedAtTheCallSite()
    testAssert.equal(codesOf("nupp.log.setLevel('debug')"), "", "a known level is clean")
    testAssert.equal(codesOf("nupp.log.setModuleLevel('game.physics', 'debug')"), "", "a module level is checked")
    testAssert.equal(codesOf("nupp.log.setModuleLevel('game.physics', 'inherit')"), "", "an override can be removed")
    testAssert.equal(codesOf("nupp.log.enabled('warn')"), "", "enabled takes the same names")
    assert(
        codesOf("nupp.log.setLevel('verbose')"):find("NUPP2006") ~= nil,
        "an unknown level is not one of the level names"
    )
    assert(
        codesOf("nupp.log.setModuleLevel('game.physics', 'verbose')"):find("NUPP2006") ~= nil,
        "an unknown module level is refused"
    )
end

-- What a module logged at `level`, as recorded lines, and what it returned.
local function logged(src, level)
    local log = runtime()
    local lines, sink = recorder()
    log.setSink(sink)
    log.setLevel(level or "debug")
    local answer = run(src, "amb")
    log.setLevel("warn")

    return lines, answer
end

function M.aStatementCallWithALiteralFormatIsLowered()
    local lines = logged("nupp.log.error('id %d', 3)")
    testAssert.equal(#lines, 1, "the site emitted")
    testAssert.equal(lines[1].level, 1, "at its own severity")
    testAssert.equal(lines[1].line, 1, "the line is a constant")
    testAssert.equal(lines[1].module, "amb", "the module name is the compiled module's")
    testAssert.equal(lines[1].message, "id 3", "the message is built at the site")
end

function M.aDebugDirectiveLowersInsideTheLevelGuard()
    local src = table.concat(
        {
            "local renders = 0",
            "local record Value",
            "    function debug(self): string",
            "        renders += 1",
            "        return 'v'",
            "    end",
            "end",
            "nupp.log.debug('value=%?', new Value())",
            "return renders",
        },
        "\n"
    )
    local lines, renders = logged(src, "warn")
    testAssert.equal(#lines, 0, "a filtered site reaches no sink")
    testAssert.equal(renders, 0, "debug formatting is lazy")

    lines, renders = logged(src, "debug")
    testAssert.equal(renders, 1, "an admitted site renders once")
    testAssert.equal(lines[1].message, "value=v", "%? formats what debug returned")
end

function M.debugDirectivesRunThroughDirectAndMethodFormattingCalls()
    local direct, method = run(
        table.concat(
            {
                "@derive(nupp.derive.Debug)",
                "local record Value",
                "   name: string",
                "end",
                "local value = new Value(name = 'ready')",
                "return string.format('direct=%?', value), ('method=%?'):format(value)",
            },
            "\n"
        ),
        "amb"
    )
    testAssert.equal(direct, 'direct=Value { name = "ready" }')
    testAssert.equal(method, 'method=Value { name = "ready" }')
end

function M.eachSeverityCarriesItsOwnIndex()
    for index, name in ipairs({"error", "warn", "info", "debug"}) do
        local lines = logged(("nupp.log.%s('m')"):format(name))
        testAssert.equal(lines[1].level, index, name .. " tests its own level")
    end
end

-- A form that keeps its ordinary call logs the same line with the module shown as
-- `?`, and evaluates its arguments.
local function assertOrdinaryCall(src, message, why)
    local lines = logged(src)
    testAssert.equal(#lines, 1, why .. ": the call emitted")
    testAssert.equal(lines[1].module, "?", why)
    testAssert.equal(lines[1].message, message, why .. ": with its message")
end

function M.whatIsNotLoweredStaysAnOrdinaryCall()
    assertOrdinaryCall("local f = 'id %d'\nnupp.log.error(f, 3)", "id 3", "a computed format has nothing to fold")
    assertOrdinaryCall("local f = nupp.log.error\nf('id %d', 3)", "id 3", "reading the function is not calling it")

    local lines, ok = logged("local ok = nupp.log.enabled('warn')\nreturn ok")
    testAssert.equal(ok, true, "a call in value position keeps its value")
    testAssert.equal(#lines, 0, "and logs nothing")

    assertOrdinaryCall(
        table.concat(
            {
                "local record Value",
                "    function debug(self): string return 'v' end",
                "end",
                "local ignored = nupp.log.debug('value=%?', new Value())",
            },
            "\n"
        ),
        "value=v",
        "a severity call in value position keeps its call"
    )

    local reached, answer = logged(
        table.concat(
            {
                "local seen = ''",
                "local nupp = {log = {error = function(m: string): nil seen = m end}}",
                "nupp.log.error('m')",
                "return seen",
            },
            "\n"
        )
    )
    testAssert.equal(answer, "m", "a local called nupp is the one that was written")
    testAssert.equal(#reached, 0, "and the logger is not reached")
end

function M.aNamedArgumentKeepsTheOrdinaryCall()
    -- Named arguments are positional only after the adjustment the ordinary call path
    -- performs, and lowering goes around it.
    assertOrdinaryCall("nupp.log.error(fmt = 'plain')", "plain", "a named argument keeps its call")
end

function M.aPluckedArgumentKeepsTheOrdinaryCall()
    assertOrdinaryCall(
        table.concat(
            {
                "local record Message",
                "    fmt: string",
                "end",
                "local message = new Message(fmt = 'plain')",
                "nupp.log.error({fmt} = message)",
            },
            "\n"
        ),
        "plain",
        "a plucked argument keeps its call"
    )
end

function M.aLoweredSiteDoesNotEvaluateAFilteredArgument()
    local log = runtime()
    local lines, sink = recorder()
    log.setSink(sink)
    log.setLevel("warn")

    local calls = 0

    local function expensive()
        calls = calls + 1
        return calls
    end

    -- What a lowered `nupp.log.debug("%d", expensive())` compiles to.
    if log.on[4] then
        log.emit(4, "amb", 7, string.format("%d", expensive()))
    end
    testAssert.equal(calls, 0, "a filtered site evaluates none of its arguments")
    testAssert.equal(#lines, 0, "and reaches no sink")

    log.setLevel("debug")
    if log.on[4] then
        log.emit(4, "amb", 7, string.format("%d", expensive()))
    end
    testAssert.equal(calls, 1, "an admitted site evaluates them once")
    testAssert.equal(#lines, 1, "and reaches the sink once")
    testAssert.equal(lines[1].module, "amb", "the sink is handed the module")
    testAssert.equal(lines[1].line, 7, "and the line")
    testAssert.equal(lines[1].level, 4, "and the severity as a number")
end

function M.aNamedLoggerDefersDebugFormattingUntilTheLevelIsEnabled()
    local log = runtime()
    local lines, sink = recorder()
    log.setSink(sink)
    log.setLevel("warn")

    local calls = 0
    local value = {
        debug = function()
            calls = calls + 1
            return "rendered"
        end
    }
    local logger = log.named("named")
    logger:debug("value=%?", value)
    testAssert.equal(calls, 0, "a disabled named logger does not call debug")

    log.setLevel("debug")
    logger:debug("value=%?", value)
    testAssert.equal(calls, 1, "an enabled named logger calls debug once")
    testAssert.equal(lines[1].message, "value=rendered", "the debug value reaches the sink")
end

function M.aLevelAdmitsItselfAndEverythingAboveIt()
    local log = runtime()
    local _, sink = recorder()
    log.setSink(sink)

    log.setLevel("warn")
    assert(log.enabled("error"), "warn admits error")
    assert(log.enabled("warn"), "warn admits itself")
    assert(not log.enabled("info"), "warn excludes info")
    assert(not log.enabled("debug"), "warn excludes debug")

    log.setLevel("off")
    for _, name in ipairs({"error", "warn", "info", "debug"}) do
        assert(not log.enabled(name), "off admits nothing: " .. name)
    end

    log.setLevel("debug")
    assert(log.enabled("debug"), "debug admits everything")
end

function M.settersAnswerWhatTheyReplaced()
    local log = runtime()
    log.setLevel("warn")
    testAssert.equal(log.setLevel("info"), "warn", "the level setter answers the previous level")
    testAssert.equal(log.level(), "info", "and reading does not change it")

    local _, sink = recorder()
    local previousSink = log.setSink(sink)
    assert(previousSink ~= nil, "the sink setter answers the previous target")
    testAssert.equal(log.sink(), sink, "and reading answers the current one")

    -- The module is one process-wide singleton rather than a table a bootstrap
    -- rebuilds per test, so what a setter replaces is whatever was in force, not nil.
    local formatterBefore = log.formatter()
    local formatter = function()
        return ""
    end
    testAssert.equal(log.setFormatter(formatter), formatterBefore, "the formatter setter answers the previous formatter")
    testAssert.equal(log.formatter(), formatter, "and the new one is in force")

    local previousFormat = log.setTimestampFormat("%H ")
    assert(previousFormat ~= nil, "the timestamp format setter answers the previous one")
    testAssert.equal(log.timestampFormat(), "%H ", "and the new one is in force")
end

function M.anUnknownLevelRaisesWhereItIsNotALiteral()
    local log = runtime()
    assert(not pcall(log.setLevel, "verbose"), "an unknown level is refused")
    assert(not pcall(log.setModuleLevel, "test.scoped.invalid", "verbose"), "including for a module")
    assert(not pcall(log.setModuleLevel, 3, "debug"), "a module name must be a string")
    assert(not pcall(log.enabled, "verbose"), "including when only asked about")
    assert(not pcall(log.setSink, 3), "a target that is neither function nor file is refused")
    assert(not pcall(log.setSink, {}), "a table without a writer is not file-like")
    assert(not pcall(log.setFormatter, "text"), "a formatter that is not a function is refused")
    assert(not pcall(log.named, 3), "a name that is not a string is refused")
end

function M.theTimestampIsCachedToTheSecond()
    local log = runtime()
    log.setTimestampFormat("%Y-%m-%d %H:%M:%S ")
    -- Take the pair just after the clock ticks, so the two reads have a whole
    -- second ahead of them rather than whatever is left of the one they landed
    -- in. Asked at an arbitrary instant they straddle a tick sooner or later,
    -- and a run that did answered two different strings for the right reason --
    -- which is the cache working, reported as the cache broken.
    local tick = os.time()
    while os.time() == tick do
    end
    local first = log.timestamp()
    testAssert.equal(log.timestamp(), first, "two reads in one second answer one string")
    assert(#first > 0, "and it is not empty")

    log.setTimestampFormat("")
    testAssert.equal(log.timestamp(), "", "an empty format turns timestamps off")

    log.setTimestampFormat("%H:%M:%S ")
    assert(log.timestamp() ~= first, "changing the format drops the cached value")
end

function M.aFileLikeTargetRendersThroughTheFormatter()
    local log = runtime()
    local written = {}
    local file = {
        write = function(_, ...)
            written[#written + 1] = table.concat({...})
            return true
        end
    }
    log.setTimestampFormat("")
    log.setLevel("debug")
    log.setSink(file)

    log.emit(1, "amb", 12, "boom")
    assert(written[1]:find("error", 1, true) ~= nil, "the default rendering names the level")
    assert(written[1]:find("amb:12", 1, true) ~= nil, "and locates the site")
    assert(written[1]:find("boom", 1, true) ~= nil, "and carries the message")

    log.setFormatter(function(level, module, line, message, stamp)
        return ("<%d|%s|%d|%s|%s>"):format(level, module, line, message, stamp)
    end)
    log.emit(2, "amb", 13, "again")
    assert(written[2]:find("<2|amb|13|again|>", 1, true) ~= nil, "an installed formatter owns the line")
end

function M.aSinkFunctionBypassesFormattingEntirely()
    local log = runtime()
    local lines, sink = recorder()
    log.setLevel("debug")
    log.setFormatter(function()
        error("a sink function must not be formatted for")
    end)
    log.setSink(sink)

    log.emit(3, "amb", 4, "message")
    testAssert.equal(#lines, 1, "the sink received the line")
    testAssert.equal(lines[1].message, "message", "unrendered")
end

function M.aNamedLoggerCarriesItsNameAndNoLine()
    local log = runtime()
    local lines, sink = recorder()
    log.setSink(sink)
    log.setLevel("debug")

    local physics = log.named("physics")
    testAssert.equal(log.named("physics"), physics, "a repeated name answers the same logger")
    physics:warn("step %d", 3)
    testAssert.equal(#lines, 1, "the named logger emitted")
    testAssert.equal(lines[1].module, "physics", "under its own name")
    testAssert.equal(lines[1].line, 0, "with no line to attribute")
    testAssert.equal(lines[1].message, "step 3", "and its formatted message")
    assert(physics:enabled("debug"), "and answers about its own levels")
end

function M.changingTheLevelRestampsExistingLoggers()
    local log = runtime()
    local lines, sink = recorder()
    log.setSink(sink)
    log.setLevel("debug")

    local physics = log.named("physics")
    physics:debug("first")
    testAssert.equal(#lines, 1, "debug is admitted")

    log.setLevel("error")
    physics:debug("second")
    testAssert.equal(#lines, 1, "a logger made before the change is restamped")

    log.setLevel("debug")
    physics:debug("third")
    testAssert.equal(#lines, 2, "and restamped back")
end

function M.aModuleLevelOverridesOnlyThatExactModule()
    local log = runtime()
    log.setLevel("warn")

    local physics = log.forModule("test.scoped.physics")
    local collision = log.forModule("test.scoped.physics.collision")
    local render = log.forModule("test.scoped.render")
    testAssert.equal(log.forModule("test.scoped.physics"), physics, "a module view is cached")

    testAssert.equal(log.setModuleLevel("test.scoped.physics", "debug"), "warn", "setting answers the inherited level")
    assert(physics.on[4], "the selected module admits debug")
    assert(not collision.on[4], "a child module does not inherit an exact override")
    assert(not render.on[4], "an unrelated module keeps the global level")
    testAssert.equal(log.moduleLevel("test.scoped.physics"), "debug", "the effective override can be read")

    log.setLevel("error")
    assert(physics.on[4], "a global change leaves the override in place")
    assert(collision.on[1] and not collision.on[2], "an inheriting module follows the global change")

    testAssert.equal(log.setModuleLevel("test.scoped.physics", "inherit"), "debug", "inherit answers the replaced override")
    testAssert.equal(log.moduleLevel("test.scoped.physics"), "error", "inherit restores the effective global level")
    assert(physics.on[1] and not physics.on[2], "the existing view resumes inheritance")

    log.setModuleLevel("test.scoped.physics", "off")
    assert(not physics.on[1], "off is retained as a real override")
    log.setModuleLevel("test.scoped.physics", "inherit")
end

function M.aModuleLevelConfiguredBeforeTheViewIsCreatedIsApplied()
    local log = runtime()
    log.setLevel("warn")

    log.setModuleLevel("test.scoped.future", "info")
    local future = log.forModule("test.scoped.future")
    assert(future.on[3], "a future view receives its override")
    assert(not future.on[4], "the override still filters lower severities")

    log.setModuleLevel("test.scoped.future", "inherit")
end

function M.aNamedLoggerUsesTheLevelForItsName()
    local log = runtime()
    local lines, sink = recorder()
    log.setSink(sink)
    log.setLevel("warn")

    local name = "test.scoped.named"
    local logger = log.named(name)
    log.setModuleLevel(name, "debug")
    assert(logger:enabled("debug"), "the named logger sees its override")
    logger:debug("selected")
    testAssert.equal(#lines, 1, "the override admits the named logger")

    log.setModuleLevel(name, "inherit")
    assert(not logger:enabled("debug"), "the named logger resumes inheritance")
    logger:debug("filtered")
    testAssert.equal(#lines, 1, "the inherited global level filters it again")
end

function M.levelNamesRoundTrip()
    local log = runtime()
    for index, name in ipairs({"error", "warn", "info", "debug"}) do
        testAssert.equal(log.levelName(index), name, "severity " .. index .. " names itself")
    end
    testAssert.equal(log.levelName(0), "off", "and zero is off")
end

function M.theLoggingViewLandsOnlyInModulesThatLog()
    local without = compile("local m = {}\nreturn m", "amb")
    testAssert.equal(without:find("nupp.log", 1, true), nil, "a module that never logs requires no logging module")
end

-- Every call written through the `nupp.log` path runs from a generated module rather
-- than only checking. The path reaches the module table; the lowered severity sites
-- reach a per-module view carrying only `on` and `emit`, and a module that did both
-- used to hand the path the view, so `nupp.log.level()` called nil (ER-009).
function M.everyPathCallRunsFromAModule()
    local log = runtime()
    local saved = {sink = log.sink(), formatter = log.formatter(), stamp = log.timestampFormat()}
    log.setLevel("warn")
    local module = run(
        table.concat(
            {
                "return function(sink: nupp.log.Sink): {any}",
                "    local answers: {any} = {}",
                "    answers[#answers + 1] = nupp.log.setLevel('debug')",
                "    answers[#answers + 1] = nupp.log.level()",
                "    answers[#answers + 1] = nupp.log.setModuleLevel('amb.other', 'error')",
                "    answers[#answers + 1] = nupp.log.moduleLevel('amb.other')",
                "    answers[#answers + 1] = nupp.log.setModuleLevel('amb.other', 'inherit')",
                "    answers[#answers + 1] = nupp.log.enabled('info')",
                "    answers[#answers + 1] = nupp.log.setTimestampFormat('')",
                "    answers[#answers + 1] = nupp.log.timestampFormat()",
                "    answers[#answers + 1] = nupp.log.timestamp()",
                "    nupp.log.setFormatter(function(level: integer, module: string, line: integer, message: string, stamp: string): string",
                "        return message",
                "    end)",
                "    answers[#answers + 1] = nupp.log.formatter() ~= nil",
                "    nupp.log.setFormatter(nil)",
                "    nupp.log.setSink(sink)",
                "    answers[#answers + 1] = nupp.log.sink() == sink",
                "    answers[#answers + 1] = nupp.log.levelName(3)",
                "    nupp.log.named('amb.named'):info('named %d', 1)",
                "    nupp.log.info('lowered %d', 2)",
                "    return answers",
                "end",
            },
            "\n"
        ),
        "amb"
    )
    local lines, sink = recorder()
    local answers = module(sink)
    log.setSink(saved.sink)
    log.setFormatter(saved.formatter)
    log.setTimestampFormat(saved.stamp)
    log.setLevel("warn")
    local want = {"warn", "debug", "debug", "error", "error", true, saved.stamp, "", "", true, true, "info",}
    for index, value in ipairs(want) do
        testAssert.equal(answers[index], value, "path call " .. index)
    end
    testAssert.equal(#lines, 2, "the named logger and the lowered site both reached the sink")
    testAssert.equal(lines[1].module, "amb.named", "the named logger carries its name")
    testAssert.equal(lines[2].module, "amb", "the lowered site carries the module")
end

return M
