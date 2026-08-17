-- Every JSON codec in the compiler says what it does with an empty table and with a
-- NaN, rather than inheriting it.
--
-- cjson's defaults are a property of the build, not of the library: this one decodes
-- `NaN` and `Infinity` happily and encodes an empty table as `{}`, and a build with
-- invalid numbers compiled out starts strict. So a codec that leaves the question open
-- answers differently under a stamped host binary than under whichever cjson an
-- interpreter found, and the same command reads its own cache file two ways. Stating
-- the policy at the site that creates the codec is what makes the answer the program's
-- rather than the host's.
--
-- This walks the sources rather than checking a list, so a codec added tomorrow is held
-- to the same rule on the run that adds it.

local fs = require("nupp.compiler.fs")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local SRC = HERE .. "/../src"

-- `nupp.data.json` is the public surface, and it hands a program cjson's own semantics
-- on purpose: `docs/json.md` documents the configuration methods as cjson's, and a
-- program that wants a different policy sets it there. The runtime is also emitted as
-- one minified line, which nothing here could read anyway.
local EXEMPT = {["nupp/compiler/stdlib.nupp"] = true}

local ENCODE = {"encode_empty_table_as_object", "encode_invalid_numbers"}
local DECODE = {"decode_array_with_array_mt", "decode_invalid_numbers"}

-- The codecs a file makes, by the local name each is bound to. One comes from cjson
-- itself; the other comes from an existing codec's `new`, which is how a file gets a
-- second one configured differently from the first.
local function codecsIn(source)
   local names = {}
   for name in source:gmatch("local%s+([%w_]+)%s*=%s*require%(\"cjson[%w.]*\"%)") do
      names[name] = true
   end
   local found = true
   while found do
      found = false
      for name, from in source:gmatch("local%s+([%w_]+)%s*=%s*([%w_]+)%.new%(%)") do
         if names[from] and not names[name] then
            names[name], found = true, true
         end
      end
   end

   return names
end

-- A codec used only to make other codecs states nothing; one that encodes owes the
-- encoding settings, one that decodes owes the decoding ones. A codec handed to
-- another module owes both, since what it will be asked to do is no longer visible
-- here.
local function directionsOf(source, name)
   local encodes = source:find(name .. "%.encode[(,]") ~= nil
   local decodes = source:find(name .. "%.decode[(,]") ~= nil
   local escapes = source:find("[%w_]+%.[%w_]+%s*=%s*" .. name .. "%s*\n") ~= nil
      or source:find("return%s+" .. name .. "%s*\n") ~= nil

   return encodes or escapes, decodes or escapes
end

local function sources()
   local out = {}
   for _, path in ipairs(fs.listFiles(SRC)) do
      if path:match("%.nupp$") and not path:match("%.d%.nupp$") then
         out[#out + 1] = path
      end
   end
   assert(#out > 0, "no sources found under " .. SRC)

   return out
end

local M = {}

function M.everyCodecStatesItsPolicy()
   local missing = {}
   local checked = 0
   for _, path in ipairs(sources()) do
      local relative = path:gsub("^.*/src/", "")
      if not EXEMPT[relative] then
         local source = assert(fs.readFile(path), "cannot read " .. path)
         for name in pairs(codecsIn(source)) do
            local encodes, decodes = directionsOf(source, name)
            local owed = {}
            if encodes then
               for _, setting in ipairs(ENCODE) do owed[#owed + 1] = setting end
            end
            if decodes then
               for _, setting in ipairs(DECODE) do owed[#owed + 1] = setting end
            end
            if #owed > 0 then checked = checked + 1 end
            for _, setting in ipairs(owed) do
               if not source:find(name .. "%." .. setting .. "%(") then
                  missing[#missing + 1] = ("%s: %s.%s is never set"):format(
                     relative, name, setting)
               end
            end
         end
      end
   end
   -- A rule nothing is held to passes for the wrong reason, so say what was looked at.
   assert(checked >= 10, "expected the compiler's JSON codecs, found " .. checked)
   assert(#missing == 0, "codecs inheriting a cjson default:\n  "
      .. table.concat(missing, "\n  "))
end

-- The half of the policy the defaults get wrong, pinned so a cjson upgrade that changes
-- them is a failing test rather than a compiler that quietly accepts `NaN`.
function M.strictNumbersAreNotTheDefault()
   local codec = require("cjson").new()
   assert(codec.decode_invalid_numbers() == true,
      "cjson still decodes NaN by default; if it no longer does, the sweep above is "
      .. "belt and braces rather than the thing that makes decoding strict")
   codec.decode_invalid_numbers(false)
   assert(not pcall(codec.decode, "[NaN]"), "a strict decoder rejects NaN")
   assert(not pcall(codec.decode, "[Infinity]"), "a strict decoder rejects Infinity")
end

return M
