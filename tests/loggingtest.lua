local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local stdlib = require("nupp.compiler.stdlib")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

-- Check, then generate under the module name a logged line should carry.
local function compile(src, moduleName)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local diags = check.check(result, "test.g.nupp", env)
   assertEq(#diags, 0, diags[1] and diags[1].msg or "check diagnostics")
   result.moduleName = moduleName or "test"
   local code, generated = gen.generate(result, moduleName or "test")
   assertEq(#generated, 0, "gen diagnostics")
   return code
end

local function codesOf(src)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax errors in test source")
   local out = {}
   for _, d in ipairs(check.check(result, "test.g.nupp", env)) do
      out[#out + 1] = d.code
   end
   return table.concat(out, " ")
end

-- The installed runtime, loaded standalone so behaviour can be exercised without
-- generating a module around it. `_G.nupp` is what the bootstrap populates.
local function runtime()
   local source = stdlib.bootstrap({["stdlib.log"] = true})
   local chunk = assert(loadstring(source, "@bootstrap"))
   chunk()
   return _G.nupp.log
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
   assertEq(codesOf("nupp.log.error('id %d', 3)"), "", "a well-formed call is clean")
   assertEq(codesOf("nupp.log.error('id %d')"), "NUPP2006",
      "a directive with no argument is reported")
   assertEq(codesOf("nupp.log.info('%s and %d', 'a', 'b')"), "NUPP2006",
      "an argument of the wrong type is reported")
   assertEq(codesOf("nupp.log.debug('plain')"), "", "a format with no directives is clean")
   assertEq(codesOf(table.concat({
      "@derive(nupp.derive.Debug)",
      "local record Value end",
      "nupp.log.debug('value=%?', new Value())",
   }, "\n")), "", "a debug directive accepts nupp.Debug")
   assertEq(codesOf("nupp.log.debug('value=%?', 'wrong')"), "NUPP2006",
      "a debug directive requires nupp.Debug")
   assertEq(codesOf(table.concat({
      "local logger = nupp.log.named('named')",
      "logger:debug('value=%?', 'wrong')",
   }, "\n")), "NUPP2006", "a named logger requires the same contract")
end

function M.levelNamesAreCheckedAtTheCallSite()
   assertEq(codesOf("nupp.log.level('debug')"), "", "a known level is clean")
   assertEq(codesOf("nupp.log.enabled('warn')"), "", "enabled takes the same names")
   assertTrue(codesOf("nupp.log.level('verbose')"):find("NUPP2125") ~= nil,
      "an unknown level selects no overload")
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
   local code = compile("nupp.log.error('id %d', 3)", "amb")
   local severity, line, message = loweredSite(code)
   assertEq(severity, 1, "the level test stands at the call site")
   assertEq(line, 1, "the line is a constant")
   assertTrue(message:find("string.format", 1, true) ~= nil,
      "the message is built at the site")
   assertTrue(code:find('_G.nupp.log.forModule("amb")', 1, true) ~= nil,
      "the module name is named once, in the prologue")
end

function M.aFormatWithNoArgumentsSkipsStringFormat()
   local code = compile("nupp.log.warn('plain')", "amb")
   local severity, _, message = loweredSite(code)
   assertEq(severity, 2, "the call was lowered")
   assertEq(message:find("string.format", 1, true), nil,
      "nothing to interpolate means nothing to call")
   assertTrue(message:find("plain", 1, true) ~= nil, "the literal is passed straight through")
end

function M.aDebugDirectiveLowersInsideTheLevelGuard()
   local code = compile(table.concat({
      "@derive(nupp.derive.Debug)",
      "local record Value end",
      "nupp.log.debug('value=%?', new Value())",
   }, "\n"), "amb")
   local guard = assert(code:find("if __nupp", 1, true), "the enabled guard is present")
   local call = assert(code:find("__nuppFormat", guard, true), "formatting happens in the guard")
   assertTrue(guard < call, "debug formatting is lazy")
   assertTrue(code:find('string.format("value=%s",__nuppA1:debug())', 1, true) ~= nil,
      "the shared helper rewrites %? to %s and calls debug")
end

function M.debugDirectivesRunThroughDirectAndMethodFormattingCalls()
   local code = compile(table.concat({
      "@derive(nupp.derive.Debug)",
      "local record Value",
      "   name: string",
      "end",
      "local value = new Value(name = 'ready')",
      "return string.format('direct=%?', value), ('method=%?'):format(value)",
   }, "\n"), "amb")
   local chunk, why = loadstring(code, "@debug-format")
   assertTrue(chunk ~= nil, why)
   local direct, method = chunk()
   assertEq(direct, 'direct=Value { name = "ready" }')
   assertEq(method, 'method=Value { name = "ready" }')
end

function M.eachSeverityCarriesItsOwnIndex()
   for index, name in ipairs({"error", "warn", "info", "debug"}) do
      local severity = loweredSite(compile(("nupp.log.%s('m')"):format(name), "amb"))
      assertEq(severity, index, name .. " tests its own level")
   end
end

function M.theLoggingViewIsBoundAfterTheInstallerThatPublishesIt()
   local code = compile("nupp.log.warn('m')", "amb")
   local installed = assert(code:find('rawset(__nupp,"log"', 1, true),
      "the installer is emitted")
   local bound = assert(code:find("_G.nupp.log.forModule(", 1, true),
      "the module view is bound")
   assertTrue(installed < bound,
      "a view of the logging table cannot be taken before the table exists")
end

-- The guard is what lowering produces, so its absence is what says a site kept its
-- ordinary call. A module reaching `nupp.log` at all still carries the installer,
-- whether or not any of its sites were lowered.
local function isLowered(code)
   return loweredSite(code) ~= nil
end

function M.whatIsNotLoweredStaysAnOrdinaryCall()
   assertTrue(not isLowered(compile("local f = 'id %d'\nnupp.log.error(f, 3)", "amb")),
      "a computed format has nothing to fold")

   assertTrue(not isLowered(compile("local f = nupp.log.error\nf('id %d', 3)", "amb")),
      "reading the function is not calling it")

   assertTrue(not isLowered(compile("local ok = nupp.log.enabled('warn')", "amb")),
      "a call in value position keeps its value")

   local valueCall = compile(table.concat({
      "@derive(nupp.derive.Debug)",
      "local record Value end",
      "local ignored = nupp.log.debug('value=%?', new Value())",
   }, "\n"), "amb")
   assertTrue(not isLowered(valueCall), "a severity call in value position keeps its call")
   assertTrue(valueCall:find(".debug", 1, true) ~= nil,
      "and is not replaced by a formatting expression")

   assertTrue(not isLowered(compile(table.concat({
      "local nupp = {log = {error = function(m: string): nil print(m) end}}",
      "nupp.log.error('m')",
   }, "\n"), "amb")), "a local called nupp is the one that was written")
end

function M.aNamedArgumentKeepsTheOrdinaryCall()
   -- Named arguments are positional only after the adjustment the ordinary call path
   -- performs, and lowering goes around it.
   assertTrue(not isLowered(compile("nupp.log.error(fmt = 'plain')", "amb")),
      "a named argument keeps its call")
end

function M.aPluckedArgumentKeepsTheOrdinaryCall()
   local code = compile(table.concat({
      "local record Message",
      "    fmt: string",
      "end",
      "local message = new Message(fmt = 'plain')",
      "nupp.log.error((fmt) = message)",
   }, "\n"), "amb")
   assertTrue(not isLowered(code), "a plucked argument keeps its call")
end

function M.aLoweredSiteDoesNotEvaluateAFilteredArgument()
   local log = runtime()
   local lines, sink = recorder()
   log.sink(sink)
   log.level("warn")

   local calls = 0
   local function expensive()
      calls = calls + 1
      return calls
   end

   -- What a lowered `nupp.log.debug("%d", expensive())` compiles to.
   if log.on[4] then log.emit(4, "amb", 7, string.format("%d", expensive())) end
   assertEq(calls, 0, "a filtered site evaluates none of its arguments")
   assertEq(#lines, 0, "and reaches no sink")

   log.level("debug")
   if log.on[4] then log.emit(4, "amb", 7, string.format("%d", expensive())) end
   assertEq(calls, 1, "an admitted site evaluates them once")
   assertEq(#lines, 1, "and reaches the sink once")
   assertEq(lines[1].module, "amb", "the sink is handed the module")
   assertEq(lines[1].line, 7, "and the line")
   assertEq(lines[1].level, 4, "and the severity as a number")
end

function M.aNamedLoggerDefersDebugFormattingUntilTheLevelIsEnabled()
   local log = runtime()
   local lines, sink = recorder()
   log.sink(sink)
   log.level("warn")

   local calls = 0
   local value = {debug = function()
      calls = calls + 1
      return "rendered"
   end}
   local logger = log.named("named")
   logger:debug("value=%?", value)
   assertEq(calls, 0, "a disabled named logger does not call debug")

   log.level("debug")
   logger:debug("value=%?", value)
   assertEq(calls, 1, "an enabled named logger calls debug once")
   assertEq(lines[1].message, "value=rendered", "the debug value reaches the sink")
end

function M.aLevelAdmitsItselfAndEverythingAboveIt()
   local log = runtime()
   local _, sink = recorder()
   log.sink(sink)

   log.level("warn")
   assertTrue(log.enabled("error"), "warn admits error")
   assertTrue(log.enabled("warn"), "warn admits itself")
   assertTrue(not log.enabled("info"), "warn excludes info")
   assertTrue(not log.enabled("debug"), "warn excludes debug")

   log.level("off")
   for _, name in ipairs({"error", "warn", "info", "debug"}) do
      assertTrue(not log.enabled(name), "off admits nothing: " .. name)
   end

   log.level("debug")
   assertTrue(log.enabled("debug"), "debug admits everything")
end

function M.settersAnswerWhatTheyReplaced()
   local log = runtime()
   log.level("warn")
   assertEq(log.level("info"), "warn", "the level setter answers the previous level")
   assertEq(log.level(), "info", "and reading does not change it")

   local _, sink = recorder()
   local previousSink = log.sink(sink)
   assertTrue(previousSink ~= nil, "the sink setter answers the previous target")
   assertEq(log.sink(), sink, "and reading answers the current one")

   local formatter = function() return "" end
   assertEq(log.formatter(formatter), nil, "no formatter was installed to begin with")
   assertEq(log.formatter(), formatter, "and the new one is in force")

   local previousFormat = log.timestampFormat("%H ")
   assertTrue(previousFormat ~= nil, "the timestamp format setter answers the previous one")
   assertEq(log.timestampFormat(), "%H ", "and the new one is in force")
end

function M.anUnknownLevelRaisesWhereItIsNotALiteral()
   local log = runtime()
   assertTrue(not pcall(log.level, "verbose"), "an unknown level is refused")
   assertTrue(not pcall(log.enabled, "verbose"), "including when only asked about")
   assertTrue(not pcall(log.sink, 3), "a target that is neither function nor file is refused")
   assertTrue(not pcall(log.formatter, "text"), "a formatter that is not a function is refused")
   assertTrue(not pcall(log.named, 3), "a name that is not a string is refused")
end

function M.theTimestampIsCachedToTheSecond()
   local log = runtime()
   log.timestampFormat("%Y-%m-%d %H:%M:%S ")
   local first = log.timestamp()
   assertEq(log.timestamp(), first, "two reads in one second answer one string")
   assertTrue(#first > 0, "and it is not empty")

   log.timestampFormat("")
   assertEq(log.timestamp(), "", "an empty format turns timestamps off")

   log.timestampFormat("%H:%M:%S ")
   assertTrue(log.timestamp() ~= first, "changing the format drops the cached value")
end

function M.aFileLikeTargetRendersThroughTheFormatter()
   local log = runtime()
   local written = {}
   local file = {write = function(_, ...)
      written[#written + 1] = table.concat({...})
      return true
   end}
   log.timestampFormat("")
   log.level("debug")
   log.sink(file)

   log.emit(1, "amb", 12, "boom")
   assertTrue(written[1]:find("error", 1, true) ~= nil, "the default rendering names the level")
   assertTrue(written[1]:find("amb:12", 1, true) ~= nil, "and locates the site")
   assertTrue(written[1]:find("boom", 1, true) ~= nil, "and carries the message")

   log.formatter(function(level, module, line, message, stamp)
      return ("<%d|%s|%d|%s|%s>"):format(level, module, line, message, stamp)
   end)
   log.emit(2, "amb", 13, "again")
   assertTrue(written[2]:find("<2|amb|13|again|>", 1, true) ~= nil,
      "an installed formatter owns the line")
end

function M.aSinkFunctionBypassesFormattingEntirely()
   local log = runtime()
   local lines, sink = recorder()
   log.level("debug")
   log.formatter(function() error("a sink function must not be formatted for") end)
   log.sink(sink)

   log.emit(3, "amb", 4, "message")
   assertEq(#lines, 1, "the sink received the line")
   assertEq(lines[1].message, "message", "unrendered")
end

function M.aNamedLoggerCarriesItsNameAndNoLine()
   local log = runtime()
   local lines, sink = recorder()
   log.sink(sink)
   log.level("debug")

   local physics = log.named("physics")
   assertEq(log.named("physics"), physics, "a repeated name answers the same logger")
   physics:warn("step %d", 3)
   assertEq(#lines, 1, "the named logger emitted")
   assertEq(lines[1].module, "physics", "under its own name")
   assertEq(lines[1].line, 0, "with no line to attribute")
   assertEq(lines[1].message, "step 3", "and its formatted message")
   assertTrue(physics:enabled("debug"), "and answers about its own levels")
end

function M.changingTheLevelRestampsExistingLoggers()
   local log = runtime()
   local lines, sink = recorder()
   log.sink(sink)
   log.level("debug")

   local physics = log.named("physics")
   physics:debug("first")
   assertEq(#lines, 1, "debug is admitted")

   log.level("error")
   physics:debug("second")
   assertEq(#lines, 1, "a logger made before the change is restamped")

   log.level("debug")
   physics:debug("third")
   assertEq(#lines, 2, "and restamped back")
end

function M.levelNamesRoundTrip()
   local log = runtime()
   for index, name in ipairs({"error", "warn", "info", "debug"}) do
      assertEq(log.levelName(index), name, "severity " .. index .. " names itself")
   end
   assertEq(log.levelName(0), "off", "and zero is off")
end

function M.theInstallerLandsOnlyInModulesThatLog()
   local without = compile("local m = {}\nreturn m", "amb")
   assertEq(without:find("nupp.log", 1, true), nil,
      "a module that never logs carries no logging runtime")

   local with = compile("nupp.log.warn('m')", "amb")
   assertTrue(with:find('rawset(__nupp,"log"', 1, true) ~= nil,
      "and a module that logs carries it")
end

return M
