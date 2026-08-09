-- The worked examples in the diagnostic catalogue, compiled.
--
-- An example that no longer reports the code it is filed under is worse than no
-- example, because it is read as authoritative. So every `wrong` is compiled and
-- has to report its code, and every `right` is compiled and has to not.
local explain = require("compiler.explain")
local json = require("cjson").new()

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function tempProject(source)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   local file = assert(io.open(dir .. "/sample.nupp", "wb"))
   file:write(source)
   file:close()
   return dir
end

--- Every code the compiler reports for one source. A strict-only rule is asked
--- for strictly, since otherwise its example would correctly report nothing.
---
--- Through `build` rather than `check`, because the generator reports too — the
--- NUPP3 family is what a program that checks cleanly cannot be lowered to, so
--- checking it would report nothing and the example would look wrong.
local function codesFor(source, strict)
   local dir = tempProject(source)
   local pipe = assert(io.popen(("cd '%s' && '%s' build %s--json sample.nupp 2>/dev/null")
      :format(dir, NUPP, strict and "--strict " or "")))
   local out = pipe:read("*a")
   pipe:close()
   os.execute("rm -rf '" .. dir .. "'")
   local ok, decoded = pcall(json.decode, out)
   assert(ok, "build --json did not produce JSON: " .. out)
   local codes = {}
   for _, diagnostic in ipairs(decoded.diagnostics or {}) do
      if diagnostic.code then codes[diagnostic.code] = true end
   end
   return codes
end

function M.everyWrongExampleReportsTheCodeItIsFiledUnder()
   local checked = 0
   for _, entry in ipairs(explain.entries) do
      if entry.wrong then
         checked = checked + 1
         local codes = codesFor(entry.wrong, entry.strict)
         assert(codes[entry.code],
            entry.code .. ": its `wrong` example no longer reports it")
      end
   end
   assert(checked > 0, "the catalogue has worked examples to check")
end

function M.everyRightExampleReportsNothing()
   for _, entry in ipairs(explain.entries) do
      if entry.right then
         local codes = codesFor(entry.right, entry.strict)
         assert(not codes[entry.code],
            entry.code .. ": its `right` example still reports it")
      end
   end
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

function M.lookupIsCaseInsensitiveThroughTheCommand()
   local pipe = assert(io.popen(("'%s' explain nupp2119 --json 2>&1"):format(NUPP)))
   local out = pipe:read("*a")
   pipe:close()
   local decoded = json.decode(out)
   assert(decoded.code == "NUPP2119", "a lower case code resolves: " .. out)
   assert(decoded.family == false, "and has an entry of its own")
   assert(decoded.wrong and decoded.right, "with both examples")
end

return M
