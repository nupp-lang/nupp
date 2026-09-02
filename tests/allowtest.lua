-- @allow: saying that a lint is understood and unwanted here. It reaches any
-- lint, at any level, because a lint is a judgement a project may disagree
-- with. It does not reach a type error, which is not a judgement.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local compilerCheck = require("nupp.compiler.check")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- These cases are about how a level resolves, so a fixture carries one lint on
-- purpose and is read as `[1]`. A fragment also binds names it never reads, and
-- that lint reports before the one under test, so the fragment defaults go
-- underneath whatever a case asked for. A case about one of them says so and
-- wins, since its own entry is merged over these.
local function withFragmentDefaults(lints)
   local merged = {["unused-binding"] = "off", ["discarded-result"] = "off"}
   for key, value in pairs(lints or {}) do merged[key] = value end
   return merged
end

local function checkOf(src, opts)
   local result = parser.parse(src, "test.g.nupp")
   assertEq(#result.errors, 0, "syntax: "
      .. (result.errors[1] and result.errors[1].msg or ""))
   local merged = {}
   for key, value in pairs(opts or {}) do merged[key] = value end
   merged.lints = withFragmentDefaults(merged.lints)
   return check.check(result, "test.g.nupp", env, merged)
end

local function diagsOf(src, opts)
   local out = {}
   for j, d in ipairs(checkOf(src, opts)) do out[j] = d.code end
   return table.concat(out, " ")
end

local function applyFix(source, fix)
   local edits = {}
   for _, edit in ipairs(fix.edits or {}) do edits[#edits + 1] = edit end
   table.sort(edits, function(a, b) return a.offset > b.offset end)
   for _, edit in ipairs(edits) do
      source = source:sub(1, edit.offset - 1) .. edit.newText
         .. source:sub(edit.offset + edit.length)
   end
   return source
end

local COLOR = "local type Color = 'red' | 'green' | 'blue'"
local CHAIN = table.concat({
   "local function name(c: Color): string",
   "    if c == 'red' then",
   "        return 'r'",
   "    end",
   "end",
}, "\n")

local function source(...)
   return table.concat({...}, "\n")
end

-- One pair per registry entry: the smallest source that demonstrates the
-- judgement, and a neighbouring source just outside it. Keeping these keyed by
-- code makes an added lint incomplete until both sides of its boundary exist.
local lintFixtures = {
   NUPP2120 = {
      reports = "return lints.get('NUPP2107')",
      quiet = source(
         "local lints = require('nupp.compiler.lints')",
         "return lints.get('NUPP2107')"),
   },
   NUPP2107 = {
      reports = COLOR .. "\n" .. CHAIN,
      quiet = COLOR .. "\n" .. source(
         "local function name(c: Color): string",
         "    if c == 'red' then",
         "        return 'r'",
         "    else",
         "        return '?'",
         "    end",
         "end"),
   },
   NUPP2501 = {
      reports = "return ffi.cast<cstring>('a' .. 'b')",
      quiet = source(
         "local text = 'a' .. 'b'",
         "return ffi.cast<cstring>(text)"),
   },
   NUPP2502 = {
      reports = source(
         "cdef function each(fn: function(int32), n: int32)",
         "local function visit(value: int32) print(value) end",
         "local function run() each(visit, 1) end",
         "return run"),
      quiet = source(
         "cdef function each(fn: function(int32), n: int32)",
         "local function visit(value: int32) print(value) end",
         "jit.off(visit)",
         "local function run() each(visit, 1) end",
         "return run"),
   },
   NUPP2504 = {
      reports = "local value = true\nreturn !value",
      quiet = "local value = true\nreturn not value",
   },
   NUPP2505 = {
      reports = source(
         "for i = 1, 10 do",
         "   register(function() return 1 end)",
         "end"),
      quiet = source(
         "for i = 1, 10 do",
         "   register(function() return i end)",
         "end"),
   },
   NUPP2506 = {
      reports = source(
         "--- Loads a value.",
         "local function load() error('missing') end",
         "return load"),
      quiet = source(
         "--- Loads a value.",
         "--- @raises when the value is missing",
         "local function load() error('missing') end",
         "return load"),
   },
   NUPP2507 = {
      reports = "local value = 1\nreturn 2",
      quiet = "local value = 1\nreturn value",
   },
   NUPP2508 = {
      reports = source(
         "local function double(value: number): number return value * 2 end",
         "double(21)",
         "return double"),
      quiet = source(
         "local function double(value: number): number return value * 2 end",
         "local answer = double(21)",
         "return answer"),
   },
   NUPP2509 = {
      reports = source(
         "local record Vec2",
         "   x: float",
         "   y: float",
         "end"),
      quiet = source(
         "local record Vec2",
         "   x: float",
         "   label: string",
         "end"),
   },
   NUPP2510 = {
      reports = source(
         "if first then",
         "   firstAction()",
         "else",
         "   if second then secondAction() end",
         "end"),
      quiet = source(
         "if first then",
         "   firstAction()",
         "elseif second then",
         "   secondAction()",
         "end"),
   },
   NUPP2511 = {
      reports = source(
         "local interface Holds",
         "   associated type Item",
         "end",
         "local function held<T is Holds>(value: T): T.Item",
         "   return nil as any",
         "end",
         "return held(nil as any)"),
      quiet = source(
         "local interface Holds",
         "   associated type Item",
         "end",
         "local record Typed is Holds",
         "   associated type Item = string",
         "end",
         "local function held<T is Holds>(value: T): T.Item",
         "   return nil as any",
         "end",
         "return held(new Typed())"),
   },
   NUPP2512 = {
      reports = source(
         "local record Point",
         "   x: integer",
         "   y: integer",
         "end",
         "return new Point(1, 2)"),
      quiet = source(
         "local record Point",
         "   x: integer",
         "   y: integer",
         "end",
         "return new Point(x = 1, y = 2)"),
   },
   NUPP2513 = {
      reports = source(
         "@deprecated local function legacy(): integer return 1 end",
         "return legacy()"),
      quiet = source(
         "@deprecated local function legacy(): integer return 1 end",
         "return 1"),
   },
   NUPP2514 = {
      reports = source(
         "cdef function printf(format: cstring, ...): int32",
         "local function run() printf('%d', 1) end",
         "return run"),
      quiet = source(
         "cdef function printf(format: cstring, ...): int32",
         "local function run() printf('%d', 1) end",
         "jit.off(run)",
         "return run"),
   },
   NUPP2515 = {
      reports = source(
         "for _, item in ipairs(items) do",
         "   register(function() return item.id end)",
         "end"),
      quiet = source(
         "for _, item in ipairs(items) do",
         "   register(function() return item.id end)",
         "   break",
         "end"),
   },
   NUPP2516 = {
      reports = source(
         "module fixture",
         "local record Coordinate x: number end",
         "export record Point coordinate: Coordinate end"),
      quiet = source(
         "module fixture",
         "export record Coordinate x: number end",
         "export record Point coordinate: Coordinate end"),
      opts = {moduleName = "fixture"},
   },
   NUPP2518 = {
      reports = source(
         "local m = {}",
         "function m.total(): integer",
         "   local values: {integer} = {10, 20, 30}",
         "   local sum: integer = 0",
         "   for index, value in ipairs(values) do sum += index * value end",
         "   return sum",
         "end",
         "return m"),
      quiet = source(
         "local m = {}",
         "function m.total(value: integer): integer",
         "   return value * 2",
         "end",
         "return m"),
   },
}

local M = {}

local function environmentWithPreludeDiagnostic(severity)
   local original = compilerCheck.check
   compilerCheck.check = function(...)
      local diags, moduleType, exports = original(...)
      local opts = select(4, ...)
      if opts and opts.declareGlobals then
         diags[#diags + 1] = {
            code = "TEST",
            severity = severity == "warning" and "warning" or "error",
            msg = "injected prelude diagnostic",
            filename = "prelude.d.nupp",
            line = 1,
            col = 1,
            offset = 1,
            length = 1,
         }
      end
      return diags, moduleType, exports
   end
   local ok, value = pcall(envMod.new, HERE .. "/..", {config = {}})
   compilerCheck.check = original
   return ok, value
end

-- Prelude declarations are load-bearing, but a configured lint warning does not make
-- them ill-typed. Only a fatal diagnostic prevents the environment from being built.
function M.preludeWarningsDoNotBecomeTypeErrors()
   local warned, warningFailure = environmentWithPreludeDiagnostic("warning")
   assert(warned, tostring(warningFailure))

   local errored, errorFailure = environmentWithPreludeDiagnostic("error")
   assert(not errored, "an error in the prelude must still stop environment creation")
   assert(tostring(errorFailure):find("injected prelude diagnostic", 1, true), tostring(errorFailure))
end

function M.everyDiagnosticCarriesASeverity()
   local errs = checkOf('local x: number = "no"')
   assertEq(errs[1].severity, "error")
   local warns = checkOf(COLOR .. "\n" .. CHAIN)
   assertEq(warns[1].severity, "warning")
end

function M.aWarningCanBeAllowed()
   assertEq(diagsOf(COLOR .. "\n" .. CHAIN), "NUPP2107")
   assertEq(diagsOf(COLOR .. "\n@allow(NUPP2107)\n" .. CHAIN), "")
end

-- A registry entry is written by hand. A misspelled category or level would
-- make a lint that nothing could configure and nothing reported, so the shape
-- is checked here rather than at load, where a typo would brick a build tree
-- until it was deleted.
function M.everyLintIsWellFormed()
   local seen = {}
   local categoryMembers = {}
   for _, lint in ipairs(check.lints) do
      local at = "lint " .. tostring(lint.name)
      assert(lint.name and lint.name:match("^[a-z][a-z0-9-]*$"),
         at .. ": name must be kebab-case")
      assert(lint.code and lint.code:match("^NUPP%d+$"),
         at .. ": code must be NUPPnnnn")
      assert(check.lintCategories[lint.category],
         at .. ": no such category: " .. tostring(lint.category))
      categoryMembers[lint.category] = true
      -- `off` is a legal default for an opt-in category only. Everywhere else it
      -- would make a lint nothing reports and nobody meets, which is the same as
      -- not writing it; in an opt-in category being quiet is the entry's point,
      -- and `nupp lints` is where it is still met.
      assert(check.lintLevels[lint.level],
         at .. ": no such default level: " .. tostring(lint.level))
      assert(lint.level ~= "off" or check.lintOptIn[lint.category],
         at .. ": only an opt-in category may default to off")
      assert(lint.summary and lint.summary ~= "", at .. ": needs a summary")
      assert(not seen[lint.name], at .. ": duplicate name")
      assert(not seen[lint.code], at .. ": duplicate code")
      seen[lint.name], seen[lint.code] = true, true
      -- both spellings have to reach the same entry, since @allow and the
      -- manifest accept either
      assertEq(check.lintFor(lint.name), lint, at .. ": name does not resolve")
      assertEq(check.lintFor(lint.code), lint, at .. ": code does not resolve")
   end
   for category in pairs(check.lintCategories) do
      assert(categoryMembers[category],
         "lint category has no members: " .. category)
   end
end

function M.everyLintHasAReportingAndQuietFixture()
   local registered = {}
   for _, lint in ipairs(check.lints) do
      registered[lint.code] = true
      local fixture = lintFixtures[lint.code]
      assert(fixture, "lint " .. lint.name .. ": needs a fixture pair")

      local function diagnosticsFor(src)
         local opts = {}
         for key, value in pairs(fixture.opts or {}) do opts[key] = value end
         opts.lints = withFragmentDefaults({[lint.name] = "warning"})
         return checkOf(src, opts)
      end

      local reported = 0
      for _, diag in ipairs(diagnosticsFor(fixture.reports)) do
         if diag.code == lint.code then reported = reported + 1 end
      end
      assertEq(reported, 1, "lint " .. lint.name .. ": reporting fixture")

      for _, diag in ipairs(diagnosticsFor(fixture.quiet)) do
         assert(diag.code ~= lint.code,
            "lint " .. lint.name .. ": quiet fixture reported it")
      end
   end
   for code in pairs(lintFixtures) do
      assert(registered[code], "fixture has no registered lint: " .. code)
   end
end

-- A project moves a level; the level decides only whether the build stops.
function M.aProjectMovesALintsLevel()
   local src = COLOR .. "\n" .. CHAIN
   local function levelOf(lints)
      local d = checkOf(src, {lints = lints})[1]
      return d and (d.severity .. " " .. d.code) or "none"
   end
   assertEq(levelOf(nil), "warning NUPP2107", "the registry default")
   assertEq(levelOf({["exhaustiveness"] = "error"}), "error NUPP2107",
      "raised by name")
   assertEq(levelOf({["NUPP2107"] = "note"}), "note NUPP2107",
      "and by code, which means the same lint")
   assertEq(levelOf({["exhaustiveness"] = "off"}), "none",
      "off is not reported at all")
end

-- A category sets a group; a name written beside it still wins.
function M.aNameBeatsItsCategory()
   local src = COLOR .. "\n" .. CHAIN
   local d = checkOf(src, {lints = {correctness = "off"}})[1]
   assertEq(d and d.code or "none", "none", "the category reached it")
   d = checkOf(src, {lints = {
      correctness = "off", ["exhaustiveness"] = "note",
   }})[1]
   assertEq(d and d.severity or "none", "note", "the name is more specific")
end

-- The style category exists so a project that prefers `&&` can say so once.
function M.aProjectTurnsOffTheCustomaryOperatorLint()
   local src = "local a = true\nlocal b = a && a"
   local function levelOf(lints)
      local d = checkOf(src, {lints = lints})[1]
      return d and (d.severity .. " " .. d.code) or "none"
   end
   assertEq(levelOf(nil), "warning NUPP2504", "the registry default")
   assertEq(levelOf({["customary-operator"] = "off"}), "none", "by name")
   assertEq(levelOf({style = "off"}), "none", "and by category")
   assertEq(levelOf({style = "note"}), "note NUPP2504", "or moved wholesale")
end

-- A lint carries the name a person writes alongside the code tooling keys on.
function M.diagnosticsCarryTheLintName()
   local d = checkOf(COLOR .. "\n" .. CHAIN)[1]
   assertEq(d.lint, "exhaustiveness", "the name travels with the report")
   d = checkOf('local x: number = "no"')[1]
   assertEq(d.lint, nil, "a type error is not a lint and has no name")
end

function M.anErrorCannotBeAllowed()
   -- A type error is not a judgement to disagree with. The error still stands,
   -- and naming it is itself reported.
   assertEq(diagsOf('@allow(NUPP2001)\nlocal x: number = "no"'),
      "NUPP2108 NUPP2001")
   local d = checkOf('@allow(NUPP2001)\nlocal x: number = "no"')[1]
   assert(d.msg:find("not a lint", 1, true), "says why: " .. d.msg)
end

-- A lint is a judgement, so a statement may disagree with one at any level --
-- including a lint that a build would otherwise fail on. A type error is not.
function M.allowReachesALintAtAnyLevel()
   assertEq(diagsOf(COLOR .. "\n@allow\n" .. CHAIN), "")
   assertEq(diagsOf('@allow\nlocal x: number = "no"'), "NUPP2001")
end

-- The name is what a person writes; the code is what tooling keys on.
function M.allowTakesALintByNameOrCode()
   assertEq(diagsOf(COLOR .. '\n@allow("exhaustiveness")\n' .. CHAIN), "")
   assertEq(diagsOf(COLOR .. "\n@allow(NUPP2107)\n" .. CHAIN), "")
end

function M.itCoversOnlyWhatItDecorates()
   assertEq(diagsOf(COLOR .. "\n@allow(NUPP2107)\n" .. CHAIN .. "\n" .. CHAIN
      :gsub("name", "other")), "NUPP2107", "the next chain still reports")
end

function M.severalCodesAtOnce()
   local src = table.concat({
      COLOR,
      "@allow(NUPP2107, NUPP2504)",
      "do",
      CHAIN,
      "    local both = true && true",
      "end",
   }, "\n")
   assertEq(diagsOf(src, {strict = true}), "")
   assertEq(diagsOf((src:gsub("@allow%(NUPP2107, NUPP2504%)",
      "@allow(NUPP2107)")), {strict = true}), "NUPP2504")
end

function M.itReachesNestedStatements()
   assertEq(diagsOf(COLOR .. "\n@allow(NUPP2107)\ndo\n" .. CHAIN .. "\nend"), "")
end

function M.aCodeThatNeverFiresIsHarmless()
   assertEq(diagsOf(COLOR .. "\n@allow(NUPP2502)\n" .. CHAIN), "NUPP2107")
end

function M.quotedCodesWork()
   assertEq(diagsOf(COLOR .. '\n@allow("NUPP2107")\n' .. CHAIN), "")
end

function M.strictLintsAreWarnings()
   local strict = {strict = true}
   local d = checkOf("local a = true\nlocal both = a && a", strict)
   assertEq(d[1].code, "NUPP2504")
   assertEq(d[1].severity, "warning")
   assertEq(diagsOf(table.concat({
      "local a = true",
      "@allow(NUPP2504)",
      "local both = a && a",
   }, "\n"), strict), "")
end

function M.fixedWidthMigrationFixesAreComplete()
   local strict = {strict = true}
   local source = table.concat({
      "local type Small = int32",
      "local wide: number = 5",
      "local small: Small = wide",
   }, "\n")
   local diagnostics = checkOf(source, strict)
   local fixes = diagnostics[1] and diagnostics[1].fixes
   assertEq(fixes and #fixes or 0, 1, "a number can only widen the destination")
   assertEq(fixes[1].title, "change the type to `number`")
   local rewritten = applyFix(source, fixes[1])
   assertEq(diagsOf(rewritten, strict), "", "the widening fix checks")

   source = source:gsub("wide: number", "wide: integer")
   diagnostics = checkOf(source, strict)
   fixes = diagnostics[1] and diagnostics[1].fixes
   assertEq(fixes and #fixes or 0, 2, "an integer can wrap or widen")
   assertEq(fixes[1].title, "convert with `nupp.math.i32.wrap`")
   assertEq(fixes[2].title, "change the type to `integer`")
   rewritten = applyFix(source, fixes[1])
   assert(rewritten:find("nupp.math.i32.wrap(wide)", 1, true),
      "the conversion encloses the complete initializer: " .. rewritten)
   assertEq(diagsOf(rewritten, strict), "", "the conversion establishes the value")
end

function M.strictUnknownNamesOfferSafeSpellingFixes()
   local source = "local answer: number = 42\nprint(asnwer)"
   local diagnostics = checkOf(source, {strict = true})
   assertEq(diagnostics[1] and diagnostics[1].code, "NUPP2105")
   local fixes = diagnostics[1] and diagnostics[1].fixes
   assertEq(fixes and #fixes or 0, 1, "one visible name is uniquely close")
   assertEq(fixes[1].title, "change to `answer`")
   assertEq(diagsOf(applyFix(source, fixes[1]), {strict = true}), "",
      "spelling edit repairs the strict diagnostic")
end

return M
