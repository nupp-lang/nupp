-- @allow: saying that a lint is understood and unwanted here. It reaches any
-- lint, at any level, because a lint is a judgement a project may disagree
-- with. It does not reach a type error, which is not a judgement.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
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

local M = {}

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
   for _, lint in ipairs(check.lints) do
      local at = "lint " .. tostring(lint.name)
      assert(lint.name and lint.name:match("^[a-z][a-z0-9-]*$"),
         at .. ": name must be kebab-case")
      assert(lint.code and lint.code:match("^NUPP%d+$"),
         at .. ": code must be NUPPnnnn")
      assert(check.lintCategories[lint.category],
         at .. ": no such category: " .. tostring(lint.category))
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
      "@allow(NUPP2107, NUPP2503)",
      "do",
      "    local x: number = 5",
      "    local small: int32 = x",
      "end",
   }, "\n")
   assertEq(diagsOf(src, {strict = true}), "")
   assertEq(diagsOf((src:gsub("@allow%(NUPP2107, NUPP2503%)",
      "@allow(NUPP2107)")), {strict = true}), "NUPP2503")
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
   local d = checkOf("local x: number = 5\nlocal small: int32 = x", strict)
   assertEq(d[1].code, "NUPP2503")
   assertEq(d[1].severity, "warning")
   assertEq(diagsOf(table.concat({
      "local x: number = 5",
      "@allow(NUPP2503)",
      "local small: int32 = x",
   }, "\n"), strict), "")
end

function M.lossyNarrowingOffersAnExplicitCast()
   local strict = {strict = true}
   local source = table.concat({
      "local type Small = int32",
      "local wide: number = 5",
      "local small: Small = wide + 1",
   }, "\n")
   local diagnostics = checkOf(source, strict)
   local fixes = diagnostics[1] and diagnostics[1].fixes
   assertEq(fixes and #fixes or 0, 1, "one explicit narrowing fix")
   assertEq(fixes[1].title, "cast to `Small`")
   local rewritten = applyFix(source, fixes[1])
   assert(rewritten:find("local small: Small = (wide + 1) as Small", 1, true),
      "the complete initializer is parenthesized: " .. rewritten)
   assertEq(diagsOf(rewritten, strict), "", "the explicit cast discharges the lint")
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
