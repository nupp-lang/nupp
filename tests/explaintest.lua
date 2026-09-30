-- The worked examples in the diagnostic catalogue, compiled.
--
-- An example that no longer reports the code it is filed under is worse than no
-- example, because it is read as authoritative. So every `wrong` is compiled and
-- has to report its code, and every `right` is compiled and has to not.
local explain = require("nupp.tools.explain")
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

-- One build per strictness, not one per example.
--
-- The examples are three lines each and there are two hundred and fifty of
-- them, so what the catalogue cost was never compiling them: it was starting a
-- compiler two hundred and fifty times. A build of one three-line file takes
-- about a sixth of a second and nearly all of that is the process. Written into
-- one project and built together they cost ten seconds instead of ninety, and
-- say the same thing -- a diagnostic names the file it came from, so an example
-- is still read as exactly what the compiler reported about it and nothing else.
--
-- Two projects rather than one, because `--strict` decides some of the answers
-- and is a property of the run rather than of a file. Both `wrong` and `right`
-- live in the same one: they are separate modules, and a module says nothing
-- about its neighbours.
--
-- A third holds what AOT lowering refuses. Only a target whose `aot` policy
-- compiles `@aot` functions lowers them, so that project declares one, pinned to
-- aarch64 so a feature tier has the same lanes wherever the suite runs. It is
-- asked through `check`, which is the promise being kept: what a build of that
-- target would refuse, a check of it reports.
--
-- The projects outlive the suite. Removing them would take an `afterAll`, and a
-- suite carrying lifecycle hooks is never sliced across shards -- which this
-- one, among the heaviest in the run, needs to be.
local reported = {}

local function fileFor(index, which)
   return ("%s_%03d.nupp"):format(which, index)
end

--- Every code the compiler reported for every example of one strictness, by the
--- file the example was written to.
---
--- Through `build` rather than `check`, because the generator reports too — the
--- NUPP3 family is what a program that checks cleanly cannot be lowered to, so
--- checking it would report nothing and the example would look wrong.
local function reportedFor(strict, aot)
   local key = aot and "aot" or strict and "strict" or "lax"
   if reported[key] then return reported[key] end
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   if aot then
      manifest:write('return {include = {"."}, build = {targets = {aot = {kind = "modules", '
         .. 'aot = "require", aotTarget = "aarch64-apple-darwin"}}}}\n')
   else
      manifest:write('return {include = {"."}}\n')
   end
   manifest:close()
   -- A missing require is visible only when the project really contains the
   -- module the unresolved name would bind.
   local module = assert(io.open(dir .. "/mathutil.g.nupp", "wb"))
   module:write("local mathutil = {}\n"
      .. "function mathutil.double(value: number): number return value * 2 end\n"
      .. "return mathutil\n")
   module:close()

   local names = {}
   for index, entry in ipairs(explain.entries) do
      if (entry.aot and true or false) == aot
         and (aot or (entry.strict and true or false) == strict) then
         for _, which in ipairs({"wrong", "right"}) do
            if entry[which] then
               local name = fileFor(index, which)
               local file = assert(io.open(dir .. "/" .. name, "wb"))
               file:write(entry[which])
               file:close()
               names[#names + 1] = name
            end
         end
      end
   end
   local codes = {}
   reported[key] = codes
   if #names == 0 then return codes end

   local pipe = assert(io.popen(("cd '%s' && '%s' %s %s--json %s 2>/dev/null")
      :format(dir, NUPP, aot and "check" or "build", strict and "--strict " or "", table.concat(names, " "))))
   local out = pipe:read("*a")
   pipe:close()
   local ok, decoded = pcall(json.decode, out)
   assert(ok, "build --json did not produce JSON: " .. out)
   for _, diagnostic in ipairs(decoded.diagnostics or {}) do
      local file = tostring(diagnostic.file or ""):match("([^/\\]+)$")
      if file and diagnostic.code then
         codes[file] = codes[file] or {}
         codes[file][diagnostic.code] = true
      end
   end
   return codes
end

--- Every code the compiler reports for one example. A strict-only rule is asked
--- for strictly, and an AOT refusal of a target that lowers, since otherwise its
--- example would correctly report nothing.
local function codesFor(entry, index, which)
   return reportedFor(entry.strict and true or false, entry.aot and true or false)[fileFor(index, which)] or {}
end

local function everyWrongExampleReportsTheCodeItIsFiledUnder()
   local checked = 0
   for index, entry in ipairs(explain.entries) do
      if entry.wrong then
         checked = checked + 1
         local codes = codesFor(entry, index, "wrong")
         assert(codes[entry.code],
            entry.code .. ": its `wrong` example no longer reports it")
      end
   end
   assert(checked > 0, "the catalogue has worked examples to check")
end

local function everyRightExampleReportsNothing()
   for index, entry in ipairs(explain.entries) do
      if entry.right then
         local codes = codesFor(entry, index, "right")
         assert(not codes[entry.code],
            entry.code .. ": its `right` example still reports it")
      end
   end
end

-- Both catalogues read the same two bulk compiler reports. Keep them in one
-- schedulable case so slicing cannot rebuild those projects in two processes.
function M.everyWorkedExampleMatchesItsDiagnosticEntry()
   everyWrongExampleReportsTheCodeItIsFiledUnder()
   everyRightExampleReportsNothing()
end

-- What lowering refuses is reported by a check of a target that lowers, so each
-- refusal a check can report has a worked pair, checked above under such a target.
-- NUPP2909 is the one a check never reports: a build does not either.
function M.everyAotRefusalACheckReportsHasAWorkedExample()
   for _, code in ipairs({"NUPP2905", "NUPP2906", "NUPP2907", "NUPP2908"}) do
      local entry = assert(explain.lookup(code), code)
      assert(entry.aot == true, code .. " is marked as needing a target that lowers")
      assert(entry.wrong and entry.right, code .. " has both examples")
   end
   local none = assert(explain.lookup("NUPP2909"))
   assert(none.wrong == nil and none.aot == false, "NUPP2909 has no program a check reports")
   local pipe = assert(io.popen(("'%s' explain NUPP2906 --json 2>/dev/null"):format(NUPP)))
   local decoded = json.decode(pipe:read("*a"))
   pipe:close()
   assert(decoded.aot == true and decoded.strict == false, "the command says which targets report it")
end

function M.everyCodeResolvesThroughItsFamilyAtLeast()
   -- A code nobody wrote an entry for still has to explain itself, or `explain`
   -- is only useful for the codes that needed it least.
   for _, code in ipairs({"NUPP0001", "NUPP1005", "NUPP2617", "NUPP3004",
      "NUPP4001"}) do
      local entry = explain.lookup(code)
      assert(entry, code .. " does not resolve")
      assert(entry.rule ~= "" and entry.docs ~= "",
         code .. " resolves without a rule or a reference")
   end
   assert(not explain.lookup("WAT1234"), "a code from no family does not resolve")
   for _, code in ipairs({"NUPP2", "NUPP2oops", "NUPP20000", "OPT", "OPT-", "OPT-nope"}) do
      assert(not explain.lookup(code), code .. " is not a diagnostic code")
      assert(not explain.anchor(code), code .. " has no reference anchor")
   end
end

function M.catalogCodesAreUniqueSortedAndConnected()
   local previous
   for _, code in ipairs(explain.codes()) do
      assert(not previous or previous < code, code .. " is duplicated or out of order")
      previous = code
      local entry = assert(explain.lookup(code), code .. " does not resolve")
      assert(entry.code == code and entry.family == false, code .. " does not resolve to its own entry")
      assert(explain.anchor(code) == entry.docs, code .. " disagrees with its reference anchor")
      for _, related in ipairs(entry.related) do
         assert(explain.lookup(related), code .. " names unknown related code " .. related)
      end
   end
end

function M.everyCodeTheCompilerCanEmitHasAReference()
   -- Scraped from the source, so a new code added without a family shows up here
   -- rather than as a diagnostic that cannot be looked up.
   local pipe = assert(io.popen(
      ("grep -rhoE '\"NUPP[0-9]{4}\"' '%s/../src' | sort -u"):format(HERE)))
   local seen = 0
   for line in pipe:lines() do
      local code = line:gsub('"', "")
      seen = seen + 1
      assert(explain.anchor(code), code .. " has no reference anchor")
   end
   pipe:close()
   assert(seen > 50, "the scrape found the codes: " .. seen)
end

-- Every diagnostic carries a `docs` pointer, and `nupp reference --section` takes
-- the pointer itself. So each one has to lead somewhere: a section of the
-- reference, a code's entry in the diagnostic index, or a heading that exists on
-- the page it names. A pointer at a page must name the page and the heading, not
-- merely reach the codes it is carried by.
function M.everyDocsPointerLeadsToASection()
   local reference = require("nupp.tools.reference")
   local trace = require("nupp.profile.trace")
   local root = HERE .. "/.."
   local pointers = {}
   for _, code in ipairs(explain.codes()) do
      pointers[#pointers + 1] = {code, explain.lookup(code).docs}
   end
   for _, code in ipairs({"NUPP0001", "NUPP1005", "NUPP2617", "NUPP3004"}) do
      pointers[#pointers + 1] = {code, explain.lookup(code).docs}
   end
   for _, reason in ipairs(trace.records()) do
      pointers[#pointers + 1] = {reason.id, explain.reasonDocs(reason.id, reason.class)}
   end
   for _, lint in ipairs(require("nupp.compiler.lints").all) do
      pointers[#pointers + 1] = {lint.code, explain.lookup(lint.code).docs}
   end
   local unresolved = {}
   for _, pair in ipairs(pointers) do
      local code, pointer = pair[1], pair[2]
      -- One form: a documentation file and an anchor in it. Never a page alone, never a
      -- module name, and a code with no prose section points at its own index entry.
      assert(pointer:match("^docs/[%w%-_/]+%.md#[%w%-]+$"),
         code .. " points at " .. pointer .. ", which is not a file#anchor pointer")
      local path = pointer:match("^([^#]*)")
      local ok = reference.findSection(pointer) ~= nil
      if not ok then
         local found = reference.pointerSections(pointer, root)
         local origin = found[1] and found[1].section.origin
         if path:find("/", 1, true) then
            ok = origin == path or origin == "the diagnostic index"
         else
            ok = #found > 0
         end
      end
      if not ok then
         unresolved[#unresolved + 1] = code .. " -> " .. pointer
      end
   end
   assert(#unresolved == 0, "pointers that lead nowhere:\n  " .. table.concat(unresolved, "\n  "))

   local pipe = assert(io.popen(("'%s' reference --section %s 2>&1"):format(NUPP,
      "docs/learn/runtime/ownership/borrowing.md#dynamic-boundaries-and-managed-cells")))
   local out = pipe:read("*a")
   pipe:close()
   assert(out:find("# Dynamic boundaries and managed cells", 1, true), "the command follows a page pointer: " .. out)
   pipe = assert(io.popen(("'%s' reference --section docs/reference/diagnostics.md#nupp2004 2>&1"):format(NUPP)))
   out = pipe:read("*a")
   pipe:close()
   assert(out:find("From the diagnostic index.", 1, true), "and a code's index entry: " .. out)
end

-- A built-in annotation's hover links to where it is documented, and the link is
-- derived from the same repository pointer a diagnostic's `docs` carries. So each has
-- to be one `nupp reference --section` follows, and to name the page it reaches.
function M.everyAnnotationHoverLinkLeadsToASection()
   local reference = require("nupp.tools.reference")
   local annotations = require("nupp.compiler.annotations")
   local registry = annotations.new(true)
   annotations.hydrateBuiltins(registry, require("nupp.compiler.types"))
   local pointers = {}
   for name, definition in pairs(registry.byname) do
      if definition.docsPath then
         pointers[#pointers + 1] = {"@" .. name, definition.docsPath}
      end
      for memberName, member in pairs(definition.members or {}) do
         if member.docsPath then
            pointers[#pointers + 1] = {"@" .. name .. "." .. memberName, member.docsPath}
         end
      end
   end
   assert(#pointers >= 26, "every built-in annotation is reached: " .. #pointers)
   local root = HERE .. "/.."
   local unresolved = {}
   for _, pair in ipairs(pointers) do
      local name, pointer = pair[1], pair[2]
      local path = pointer:match("^([^#]*)")
      local ok = pointer:match("^docs/[%w%-_/]+%.md#[%w%-]+$") ~= nil
      if ok then
         local found = reference.pointerSections(pointer, root)
         ok = found[1] ~= nil and found[1].section.origin == path
      end
      if not ok then
         unresolved[#unresolved + 1] = name .. " -> " .. pointer
      end
   end
   table.sort(unresolved)
   assert(#unresolved == 0, "hover links that lead nowhere:\n  " .. table.concat(unresolved, "\n  "))
   local lsp = require("nupp.tools.lsp")
   assert(lsp.siteUrl("docs/reference/annotations.md#aot") == "https://nupp.org/reference/annotations#aot")
   assert(lsp.siteUrl("docs/learn/performance/ahead-of-time/index.md#annotation-guarantees")
      == "https://nupp.org/learn/performance/ahead-of-time#annotation-guarantees")
end

-- A lint is a code the compiler reports by name, and `explain --list` is where a
-- reader finds what one means. A lint without an entry of its own falls back to
-- the family's generic rule and is missing from the list.
function M.everyLintHasAnEntryOfItsOwn()
   local listed = {}
   for _, code in ipairs(explain.codes()) do
      listed[code] = true
   end
   for _, lint in ipairs(require("nupp.compiler.lints").all) do
      assert(listed[lint.code], lint.code .. " (" .. lint.name .. ") has no explain entry")
   end
end

function M.lookupIsCaseInsensitiveThroughTheCommand()
   local pipe = assert(io.popen(("'%s' explain nupp2119 --json 2>/dev/null"):format(NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   local decoded = json.decode(out)
   assert(decoded.code == "NUPP2119", "a lower case code resolves: " .. out)
   assert(decoded.family == false, "and has an entry of its own")
   assert(decoded.wrong and decoded.right, "with both examples")
end

function M.listRefusesACodeItWouldIgnore()
   local pipe = assert(io.popen(
      ("'%s' explain --list NUPP2004 2>&1; echo \"__exit__:$?\""):format(NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   assert(out:find("__exit__:2", 1, true), "a code beside --list is a usage error: " .. out)
   assert(out:find("does not take one", 1, true), "and says why: " .. out)
end

function M.malformedCodeIsAUsageErrorOnStderr()
   local stdout, stderr = os.tmpname(), os.tmpname()
   local status = os.execute(
      ("'%s' explain NUPP2wat >'%s' 2>'%s'"):format(NUPP, stdout, stderr))
   local outFile = assert(io.open(stdout, "rb"))
   local out = outFile:read("*a")
   outFile:close()
   local errFile = assert(io.open(stderr, "rb"))
   local err = errFile:read("*a")
   errFile:close()
   os.remove(stdout)
   os.remove(stderr)

   assert(status ~= 0, "a malformed code fails")
   assert(out == "", "a usage error writes no stdout: " .. out)
   assert(err:find("unknown diagnostic code NUPP2wat", 1, true), "stderr identifies the code: " .. err)
end

function M.jsonAndSchemaOutputAreByteStable()
   local function output(arguments)
      local pipe = assert(io.popen(("'%s' explain %s 2>/dev/null"):format(NUPP, arguments)))
      local out = pipe:read("*a")
      pipe:close()
      return out
   end

   for _, arguments in ipairs({"NUPP2149 --json", "--list --json", "--schema"}) do
      local first = output(arguments)
      local second = output(arguments)
      assert(first == second, arguments .. " changes bytes between processes")
   end
end

function M.traceReasonsResolveThroughTheCommand()
   local pipe = assert(io.popen(
      ("'%s' explain jit/loop-function-construction --json 2>/dev/null"):format(NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   local decoded = json.decode(out)
   assert(decoded.code == "jit/loop-function-construction", out)
   assert(decoded.class == "blocker", "the reason class is public")
   assert(decoded.repair and decoded.repair ~= "", "known reasons carry their repair")
   assert(decoded.reasonCatalog.id == "nupp-trace-reasons-v1",
      "the answer names its versioned registry")
end

return M
