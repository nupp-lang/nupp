local testAssert = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local gen = require("nupp.compiler.lua.gen")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local stdlib = require("nupp.compiler.stdlib")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

-- Check, then generate under the module name a logged line should carry.
local function compile(src, moduleName)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local diags = check.check(result, "test.nupp", env)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check diagnostics")
    result.moduleName = moduleName or "test"
    local code, generated = gen.generate(result, moduleName or "test")
    testAssert.eq(#generated, 0, "gen diagnostics")

    return code
end

local function codesOf(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax errors in test source")
    local out = {}
    for _, d in ipairs(check.check(result, "test.nupp", env)) do
        out[#out + 1] = d.code
    end

    return table.concat(out, " ")
end

-- The logging module itself, so behaviour can be exercised without generating a
-- module around it. It is an ordinary module now, not something a bootstrap installs.
local function runtime()
    return require("debug.log")
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
    testAssert.eq(codesOf("debug.log.error('id %d', 3)"), "", "a well-formed call is clean")
    testAssert.eq(codesOf("debug.log.error('id %d')"), "NUPP2006", "a directive with no argument is reported")
    testAssert.eq(
        codesOf("debug.log.info('%s and %d', 'a', 'b')"),
        "NUPP2006",
        "an argument of the wrong type is reported"
    )
    testAssert.eq(codesOf("debug.log.debug('plain')"), "", "a format with no directives is clean")
    testAssert.eq(
        codesOf(
            table.concat(
                {"@derive(types.debug)", "local record Value end", "debug.log.debug('value=%?', Value())",},
                "\n"
            )
        ),
        "",
        "a debug directive accepts types.Debug"
    )
    testAssert.eq(codesOf("debug.log.debug('value=%?', 'wrong')"), "NUPP2006", "a debug directive requires types.Debug")
    testAssert.eq(
        codesOf(table.concat({"local logger = debug.log.named('named')", "logger:debug('value=%?', 'wrong')",}, "\n")),
        "NUPP2006",
        "a named logger requires the same contract"
    )
end

function M.levelNamesAreCheckedAtTheCallSite()
    testAssert.eq(codesOf("debug.log.setlevel('debug')"), "", "a known level is clean")
    testAssert.eq(codesOf("debug.log.setmodulelevel('game.physics', 'debug')"), "", "a module level is checked")
    testAssert.eq(codesOf("debug.log.setmodulelevel('game.physics', 'inherit')"), "", "an override can be removed")
    testAssert.eq(codesOf("debug.log.enabled('warn')"), "", "enabled takes the same names")
    assert(
        codesOf("debug.log.setlevel('verbose')"):find("NUPP2006") ~= nil,
        "an unknown level is not one of the level names"
    )
    assert(
        codesOf("debug.log.setmodulelevel('game.physics', 'verbose')"):find("NUPP2006") ~= nil,
        "an unknown module level is refused"
    )
end

-- The lowered site, as severity, line and the expression built for the message. The
-- binding it reaches through is a reserved name, so it is matched rather than spelled.
local function loweredSite(code)
    local severity, line, rest = code:match("if __nupp%w*%.on%[(%d)%] then __nupp%w*%.emit%((%d),(%d+),")
    if not severity then
        return nil
    end
    local message = code:match("%.emit%(%d,%d+,(.-)%) end")

    return tonumber(severity), tonumber(rest), message
end

function M.aStatementCallWithALiteralFormatIsLowered()
    local code = compile("debug.log.error('id %d', 3)", "amb")
    local severity, line, message = loweredSite(code)
    testAssert.eq(severity, 1, "the level test stands at the call site")
    testAssert.eq(line, 1, "the line is a constant")
    assert(message:find("string.format", 1, true) ~= nil, "the message is built at the site")
    assert(
        code:find('require("debug.log").formodule("amb")', 1, true) ~= nil,
        "the module name is named once, in the prologue"
    )
end

function M.aFormatWithNoArgumentsSkipsStringFormat()
    local code = compile("debug.log.warn('plain')", "amb")
    local severity, _, message = loweredSite(code)
    testAssert.eq(severity, 2, "the call was lowered")
    testAssert.eq(message:find("string.format", 1, true), nil, "nothing to interpolate means nothing to call")
    assert(message:find("plain", 1, true) ~= nil, "the literal is passed straight through")
end

function M.aDebugDirectiveLowersInsideTheLevelGuard()
    local code = compile(
        table.concat({"@derive(types.debug)", "local record Value end", "debug.log.debug('value=%?', Value())",}, "\n"),
        "amb"
    )
    local guard = assert(code:find("if __nupp", 1, true), "the enabled guard is present")
    local call = assert(code:find("__nuppFormat", guard, true), "formatting happens in the guard")
    assert(guard < call, "debug formatting is lazy")
    assert(
        code:find('string.format("value=%s",__nuppA1:debug())', 1, true) ~= nil,
        "the shared helper rewrites %? to %s and calls debug"
    )
end

function M.debugDirectivesRunThroughDirectAndMethodFormattingCalls()
    local code = compile(
        table.concat(
            {
                "@derive(types.debug)",
                "local record Value",
                "   name: string",
                "end",
                "local value = Value(name = 'ready')",
                "return string.format('direct=%?', value), ('method=%?'):format(value)",
            },
            "\n"
        ),
        "amb"
    )
    local chunk, why = loadstring(code, "@debug-format")
    assert(chunk ~= nil, why)
    local direct, method = chunk()
    testAssert.eq(direct, 'direct=Value { name = "ready" }')
    testAssert.eq(method, 'method=Value { name = "ready" }')
end

function M.eachSeverityCarriesItsOwnIndex()
    for index, name in ipairs({"error", "warn", "info", "debug"}) do
        local severity = loweredSite(compile(("debug.log.%s('m')"):format(name), "amb"))
        testAssert.eq(severity, index, name .. " tests its own level")
    end
end

-- Logging is an ordinary module, so the view is reached through `require` and there
-- is no installer to be ordered against. What used to be an ordering rule is now
-- Lua's own module loading.
function M.theLoggingViewIsBoundThroughRequire()
    local code = compile("debug.log.warn('m')", "amb")
    assert(code:find('require("debug.log").formodule(', 1, true) ~= nil, "the module view is bound through require")
    testAssert.eq(
        code:find('rawset(__nupp,"log"', 1, true),
        nil,
        "and nothing installs a logging table into the ambient one"
    )
end

-- The guard is what lowering produces, so its absence is what says a site kept its
-- ordinary call. A module reaching `log` at all still requires it, whether or
-- not any of its sites were lowered.
local function isLowered(code)
    return loweredSite(code) ~= nil
end

function M.whatIsNotLoweredStaysAnOrdinaryCall()
    assert(
        not isLowered(compile("local f = 'id %d'\ndebug.log.error(f, 3)", "amb")),
        "a computed format has nothing to fold"
    )

    assert(
        not isLowered(compile("local f = debug.log.error\nf('id %d', 3)", "amb")),
        "reading the function is not calling it"
    )

    assert(
        not isLowered(compile("local ok = debug.log.enabled('warn')", "amb")),
        "a call in value position keeps its value"
    )

    local valueCall = compile(
        table.concat(
            {"@derive(types.debug)", "local record Value end", "local ignored = debug.log.debug('value=%?', Value())",},
            "\n"
        ),
        "amb"
    )
    assert(not isLowered(valueCall), "a severity call in value position keeps its call")
    assert(valueCall:find(".debug", 1, true) ~= nil, "and is not replaced by a formatting expression")

    assert(
        not isLowered(
            compile(
                table.concat(
                    {"local debug = {log = {error = function(m: string): nil print(m) end}}", "debug.log.error('m')",},
                    "\n"
                ),
                "amb"
            )
        ),
        "a local called debug is the one that was written"
    )
end

function M.aNamedArgumentKeepsTheOrdinaryCall()
    -- Named arguments are positional only after the adjustment the ordinary call path
    -- performs, and lowering goes around it.
    assert(not isLowered(compile("debug.log.error(fmt = 'plain')", "amb")), "a named argument keeps its call")
end

function M.aPluckedArgumentKeepsTheOrdinaryCall()
    local code = compile(
        table.concat(
            {
                "local record Message",
                "    fmt: string",
                "end",
                "local message = Message(fmt = 'plain')",
                "debug.log.error({fmt} = message)",
            },
            "\n"
        ),
        "amb"
    )
    assert(not isLowered(code), "a plucked argument keeps its call")
end

function M.aLoweredSiteDoesNotEvaluateAFilteredArgument()
    local log = runtime()
    local lines, sink = recorder()
    local previousSink = log.setsink(sink)
    local previousLevel = log.setlevel("warn")
    local code = compile(
        table.concat(
            {
                "local calls: integer = 0",
                "local function expensive(): integer",
                "    calls = calls + 1",
                "    return calls",
                "end",
                "debug.log.debug('%d', expensive())",
                "return calls",
            },
            "\n"
        ),
        "amb"
    )
    local run = assert(loadstring(code, "@lazy-debug-log"))
    local ok, reason = pcall(function()
        testAssert.eq(run(), 0, "a filtered site evaluates none of its arguments")
        testAssert.eq(#lines, 0, "and reaches no sink")
        log.setlevel("debug")
        testAssert.eq(run(), 1, "an admitted site evaluates its argument once")
        testAssert.eq(#lines, 1, "and reaches the sink once")
        testAssert.eq(lines[1].module, "amb", "the sink receives the module")
        testAssert.eq(lines[1].line, 6, "and the source line")
        testAssert.eq(lines[1].level, 4, "and the severity")
    end)
    log.setsink(previousSink)
    log.setlevel(previousLevel)
    assert(ok, reason)
end

function M.aNamedLoggerDefersDebugFormattingUntilTheLevelIsEnabled()
    local log = runtime()
    local lines, sink = recorder()
    log.setsink(sink)
    log.setlevel("warn")

    local calls = 0
    local value = {
        debug = function()
            calls = calls + 1
            return "rendered"
        end
    }
    local logger = log.named("named")
    logger:debug("value=%?", value)
    testAssert.eq(calls, 0, "a disabled named logger does not call debug")

    log.setlevel("debug")
    logger:debug("value=%?", value)
    testAssert.eq(calls, 1, "an enabled named logger calls debug once")
    testAssert.eq(lines[1].message, "value=rendered", "the debug value reaches the sink")
end

function M.aLevelAdmitsItselfAndEverythingAboveIt()
    local log = runtime()
    local _, sink = recorder()
    log.setsink(sink)

    log.setlevel("warn")
    assert(log.enabled("error"), "warn admits error")
    assert(log.enabled("warn"), "warn admits itself")
    assert(not log.enabled("info"), "warn excludes info")
    assert(not log.enabled("debug"), "warn excludes debug")

    log.setlevel("off")
    for _, name in ipairs({"error", "warn", "info", "debug"}) do
        assert(not log.enabled(name), "off admits nothing: " .. name)
    end

    log.setlevel("debug")
    assert(log.enabled("debug"), "debug admits everything")
end

function M.settersAnswerWhatTheyReplaced()
    local log = runtime()
    log.setlevel("warn")
    testAssert.eq(log.setlevel("info"), "warn", "the level setter answers the previous level")
    testAssert.eq(log.level(), "info", "and reading does not change it")

    local _, sink = recorder()
    local previousSink = log.setsink(sink)
    assert(previousSink ~= nil, "the sink setter answers the previous target")
    testAssert.eq(log.sink(), sink, "and reading answers the current one")

    -- The module is one process-wide singleton rather than a table a bootstrap
    -- rebuilds per test, so what a setter replaces is whatever was in force, not nil.
    local formatterBefore = log.formatter()
    local formatter = function()
        return ""
    end
    testAssert.eq(log.setformatter(formatter), formatterBefore, "the formatter setter answers the previous formatter")
    testAssert.eq(log.formatter(), formatter, "and the new one is in force")

    local previousFormat = log.settimestampformat("%H ")
    assert(previousFormat ~= nil, "the timestamp format setter answers the previous one")
    testAssert.eq(log.timestampformat(), "%H ", "and the new one is in force")
end

function M.anUnknownLevelRaisesWhereItIsNotALiteral()
    local log = runtime()
    assert(not pcall(log.setlevel, "verbose"), "an unknown level is refused")
    assert(not pcall(log.setmodulelevel, "test.scoped.invalid", "verbose"), "including for a module")
    assert(not pcall(log.setmodulelevel, 3, "debug"), "a module name must be a string")
    assert(not pcall(log.enabled, "verbose"), "including when only asked about")
    assert(not pcall(log.setsink, 3), "a target that is neither function nor file is refused")
    assert(not pcall(log.setsink, {}), "a table without a writer is not file-like")
    assert(not pcall(log.setformatter, "text"), "a formatter that is not a function is refused")
    assert(not pcall(log.named, 3), "a name that is not a string is refused")
end

function M.theTimestampIsCachedToTheSecond()
    local log = runtime()
    log.settimestampformat("%Y-%m-%d %H:%M:%S ")
    -- Take the pair just after the clock ticks, so the two reads have a whole
    -- second ahead of them rather than whatever is left of the one they landed
    -- in. Asked at an arbitrary instant they straddle a tick sooner or later,
    -- and a run that did answered two different strings for the right reason --
    -- which is the cache working, reported as the cache broken.
    local tick = os.time()
    while os.time() == tick do
    end
    local first = log.timestamp()
    testAssert.eq(log.timestamp(), first, "two reads in one second answer one string")
    assert(#first > 0, "and it is not empty")

    log.settimestampformat("")
    testAssert.eq(log.timestamp(), "", "an empty format turns timestamps off")

    log.settimestampformat("%H:%M:%S ")
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
    log.settimestampformat("")
    log.setlevel("debug")
    log.setsink(file)

    log.emit(1, "amb", 12, "boom")
    assert(written[1]:find("error", 1, true) ~= nil, "the default rendering names the level")
    assert(written[1]:find("amb:12", 1, true) ~= nil, "and locates the site")
    assert(written[1]:find("boom", 1, true) ~= nil, "and carries the message")

    log.setformatter(function(level, module, line, message, stamp)
        return ("<%d|%s|%d|%s|%s>"):format(level, module, line, message, stamp)
    end)
    log.emit(2, "amb", 13, "again")
    assert(written[2]:find("<2|amb|13|again|>", 1, true) ~= nil, "an installed formatter owns the line")
end

function M.theDefaultSinkPreservesFormattingWhenRestored()
    local previousLog, previousError = package.loaded["debug.log"], io.stderr
    package.loaded["debug.log"] = nil
    local ok, problem = pcall(function()
        local log = runtime()
        local written = {}
        io.stderr = {
            write = function(_, bytes)
                written[#written + 1] = bytes
                return true
            end
        }
        log.settimestampformat("")
        local default = log.sink()
        assert(type(default) == "function", "the default destination uses the callback contract")
        log.emit(2, "sample", 7, "first")
        testAssert.eq(written[1], "warn sample:7: first\n")
        log.setsink(function()
        end)
        log.setformatter(function(_, _, _, message)
            return "formatted " .. message
        end)
        log.emit(2, "sample", 0, "discarded")
        log.setsink(default)
        log.emit(2, "sample", 0, "restored")
        testAssert.eq(#written, 2)
        testAssert.eq(written[2], "formatted restored\n")
    end)
    io.stderr, package.loaded["debug.log"] = previousError, previousLog
    assert(ok, problem)
end

function M.aWriterTargetReceivesEachRenderedLine()
    local log = runtime()
    local buffer = require("io").Buffer.create()
    log.settimestampformat("")
    log.setformatter(nil)
    log.setlevel("debug")
    local previous = log.setsink(buffer:writer())
    log.emit(2, "amb", 7, "to a buffer")
    log.emit(3, "amb", 8, "and another")
    log.setsink(previous)
    local text = buffer:getstring()
    assert(text == "warn amb:7: to a buffer\ninfo amb:8: and another\n", text)
end

function M.aSinkFunctionBypassesFormattingEntirely()
    local log = runtime()
    local lines, sink = recorder()
    log.setlevel("debug")
    log.setformatter(function()
        error("a sink function must not be formatted for")
    end)
    log.setsink(sink)

    log.emit(3, "amb", 4, "message")
    testAssert.eq(#lines, 1, "the sink received the line")
    testAssert.eq(lines[1].message, "message", "unrendered")
end

function M.aNamedLoggerCarriesItsNameAndNoLine()
    local log = runtime()
    local lines, sink = recorder()
    log.setsink(sink)
    log.setlevel("debug")

    local physics = log.named("physics")
    testAssert.eq(log.named("physics"), physics, "a repeated name answers the same logger")
    physics:warn("step %d", 3)
    testAssert.eq(#lines, 1, "the named logger emitted")
    testAssert.eq(lines[1].module, "physics", "under its own name")
    testAssert.eq(lines[1].line, 0, "with no line to attribute")
    testAssert.eq(lines[1].message, "step 3", "and its formatted message")
    assert(physics:enabled("debug"), "and answers about its own levels")
end

function M.changingTheLevelRestampsExistingLoggers()
    local log = runtime()
    local lines, sink = recorder()
    log.setsink(sink)
    log.setlevel("debug")

    local physics = log.named("physics")
    physics:debug("first")
    testAssert.eq(#lines, 1, "debug is admitted")

    log.setlevel("error")
    physics:debug("second")
    testAssert.eq(#lines, 1, "a logger made before the change is restamped")

    log.setlevel("debug")
    physics:debug("third")
    testAssert.eq(#lines, 2, "and restamped back")
end

function M.aModuleLevelOverridesOnlyThatExactModule()
    local log = runtime()
    log.setlevel("warn")

    local physics = log.formodule("test.scoped.physics")
    local collision = log.formodule("test.scoped.physics.collision")
    local render = log.formodule("test.scoped.render")
    testAssert.eq(log.formodule("test.scoped.physics"), physics, "a module view is cached")

    testAssert.eq(log.setmodulelevel("test.scoped.physics", "debug"), "warn", "setting answers the inherited level")
    assert(physics.on[4], "the selected module admits debug")
    assert(not collision.on[4], "a child module does not inherit an exact override")
    assert(not render.on[4], "an unrelated module keeps the global level")
    testAssert.eq(log.modulelevel("test.scoped.physics"), "debug", "the effective override can be read")

    log.setlevel("error")
    assert(physics.on[4], "a global change leaves the override in place")
    assert(collision.on[1] and not collision.on[2], "an inheriting module follows the global change")

    testAssert.eq(
        log.setmodulelevel("test.scoped.physics", "inherit"),
        "debug",
        "inherit answers the replaced override"
    )
    testAssert.eq(log.modulelevel("test.scoped.physics"), "error", "inherit restores the effective global level")
    assert(physics.on[1] and not physics.on[2], "the existing view resumes inheritance")

    log.setmodulelevel("test.scoped.physics", "off")
    assert(not physics.on[1], "off is retained as a real override")
    log.setmodulelevel("test.scoped.physics", "inherit")
end

function M.aModuleLevelConfiguredBeforeTheViewIsCreatedIsApplied()
    local log = runtime()
    log.setlevel("warn")

    log.setmodulelevel("test.scoped.future", "info")
    local future = log.formodule("test.scoped.future")
    assert(future.on[3], "a future view receives its override")
    assert(not future.on[4], "the override still filters lower severities")

    log.setmodulelevel("test.scoped.future", "inherit")
end

function M.aNamedLoggerUsesTheLevelForItsName()
    local log = runtime()
    local lines, sink = recorder()
    log.setsink(sink)
    log.setlevel("warn")

    local name = "test.scoped.named"
    local logger = log.named(name)
    log.setmodulelevel(name, "debug")
    assert(logger:enabled("debug"), "the named logger sees its override")
    logger:debug("selected")
    testAssert.eq(#lines, 1, "the override admits the named logger")

    log.setmodulelevel(name, "inherit")
    assert(not logger:enabled("debug"), "the named logger resumes inheritance")
    logger:debug("filtered")
    testAssert.eq(#lines, 1, "the inherited global level filters it again")
end

function M.levelNamesRoundTrip()
    local log = runtime()
    for index, name in ipairs({"error", "warn", "info", "debug"}) do
        testAssert.eq(log.levelname(index), name, "severity " .. index .. " names itself")
    end
    testAssert.eq(log.levelname(0), "off", "and zero is off")
end

function M.theLoggingViewLandsOnlyInModulesThatLog()
    local without = compile("local m = {}\nreturn m", "amb")
    assert(without:find('require("debug.log")', 1, true), "startup initializes the warning function")
    assert(not without:find('.formodule(', 1, true), "a module that never logs needs no logging view")

    local with = compile("debug.log.warn('m')", "amb")
    assert(with:find('require("debug.log")', 1, true) ~= nil, "and a module that logs requires it once")
end

-- Every call written through the `log` path runs from a generated module rather
-- than only checking. The path reaches the module table; the lowered severity sites
-- reach a per-module view carrying only `on` and `emit`, and a module that did both
-- used to hand the path the view, so `log.level()` called nil (ER-009).
function M.everyPathCallRunsFromAModule()
    local log = runtime()
    local saved = {sink = log.sink(), formatter = log.formatter(), stamp = log.timestampformat()}
    log.setlevel("warn")
    local code = compile(
        table.concat(
            {
                "return function(sink: debug.log.Sink): {any}",
                "    local answers: {any} = {}",
                "    answers[#answers + 1] = debug.log.setlevel('debug')",
                "    answers[#answers + 1] = debug.log.level()",
                "    answers[#answers + 1] = debug.log.setmodulelevel('amb.other', 'error')",
                "    answers[#answers + 1] = debug.log.modulelevel('amb.other')",
                "    answers[#answers + 1] = debug.log.setmodulelevel('amb.other', 'inherit')",
                "    answers[#answers + 1] = debug.log.enabled('info')",
                "    answers[#answers + 1] = debug.log.settimestampformat('')",
                "    answers[#answers + 1] = debug.log.timestampformat()",
                "    answers[#answers + 1] = debug.log.timestamp()",
                "    debug.log.setformatter(function(level: integer, module: string, line: integer, message: string, stamp: string): string",
                "        return message",
                "    end)",
                "    answers[#answers + 1] = debug.log.formatter() ~= nil",
                "    debug.log.setformatter(nil)",
                "    local _ = debug.log.setsink(sink)",
                "    answers[#answers + 1] = debug.log.sink() == sink",
                "    answers[#answers + 1] = debug.log.levelname(3)",
                "    debug.log.named('amb.named'):info('named %d', 1)",
                "    debug.log.info('lowered %d', 2)",
                "    return answers",
                "end",
            },
            "\n"
        ),
        "amb"
    )
    local lines, sink = recorder()
    local chunk, why = loadstring(code, "@path-calls")
    assert(chunk ~= nil, why)
    local answers = chunk()(sink)
    log.setsink(saved.sink)
    log.setformatter(saved.formatter)
    log.settimestampformat(saved.stamp)
    log.setlevel("warn")
    local want = {"warn", "debug", "debug", "error", "error", true, saved.stamp, "", "", true, true, "info",}
    for index, value in ipairs(want) do
        testAssert.eq(answers[index], value, "path call " .. index)
    end
    testAssert.eq(#lines, 2, "the named logger and the lowered site both reached the sink")
    testAssert.eq(lines[1].module, "amb.named", "the named logger carries its name")
    testAssert.eq(lines[2].module, "amb", "the lowered site carries the module")
end

function M.precedingModuleViewFactoryIsAbsent()
    local log = require("debug.log")
    testAssert.eq(log.forModule, nil)
    testAssert.eq(type(log.formodule), "function")
end

function M.theFormerGlobalIsUnavailable()
    assert(codesOf("log.info('old root')") ~= "", "logging is only under debug.log")
end

return M
