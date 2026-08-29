-- Compatibility harness for the cached LuaLS source tree. It intentionally does not
-- fail on recoverable annotation warnings or on Lua syntax outside LuaJIT's dialect;
-- both are counted. An importer crash or a comment that vanishes is a failure.

local root = assert(arg[1], "usage: annotated-lua-corpus.lua TREE")
local parser = require("nupp.compiler.parser")
local annotated = require("nupp.compiler.annotatedlua")
local check = require("nupp.compiler.check")

local function quote(path)
   return "'" .. path:gsub("'", "'\\''") .. "'"
end

local pipe = assert(io.popen("find " .. quote(root) .. " -type f -name '*.lua' -print"))
local paths = {}
for path in pipe:lines() do paths[#paths + 1] = path end
assert(pipe:close())
table.sort(paths)

local files, tags, warnings, syntaxFiles, checkedFiles, checkerWarnings = 0, 0, 0, 0, 0, 0
local warningTags = {}
for _, path in ipairs(paths) do
   local handle = assert(io.open(path, "rb"))
   local source = assert(handle:read("*a"))
   handle:close()
   local result = parser.parse(source, path)
   local found = annotated.tags(source, result.tokens)
   if #found > 0 then
      files = files + 1
      tags = tags + #found
      if #result.errors > 0 then syntaxFiles = syntaxFiles + 1 end
      local ok, imported = pcall(annotated.decorate, result, path)
      if not ok then
         error(path .. ": annotation importer crashed: " .. tostring(imported), 0)
      end
      assert(#result.annotationTags == #found,
         path .. ": annotation scan changed while importing")
      warnings = warnings + #imported
      for _, item in ipairs(imported) do
         warningTags[item.msg] = (warningTags[item.msg] or 0) + 1
      end
      if #result.errors == 0 then
         local checked, diagnostics = pcall(check.check, result, path)
         if not checked then
            error(path .. ": checker crashed after annotation import: " .. tostring(diagnostics), 0)
         end
         checkedFiles = checkedFiles + 1
         for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.code == "NUPP1008" then checkerWarnings = checkerWarnings + 1 end
         end
      end
   end
end

assert(files > 0 and tags > 0, "the pinned LuaLS tree contained no annotated Lua")
io.write(("LuaLS %d annotated files, %d tags: all imported\n"):format(files, tags))
io.write(("%d recoverable annotation warnings; %d files have base syntax outside Nupp's LuaJIT grammar\n")
   :format(warnings, syntaxFiles))
io.write(("%d syntax-compatible annotated files checked; %d NUPP1008 warnings observed by the checker\n")
   :format(checkedFiles, checkerWarnings))

local summaries = {}
for message, count in pairs(warningTags) do
   summaries[#summaries + 1] = {message = message, count = count}
end
table.sort(summaries, function(a, b)
   return a.count > b.count or a.count == b.count and a.message < b.message
end)
for index = 1, math.min(#summaries, 8) do
   io.write(("  %d  %s\n"):format(summaries[index].count, summaries[index].message))
end
