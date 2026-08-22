-- Generates the portable compiler's checked prelude graph as inert data. Run
-- this under official Lua 5.1 after building the portable bundle; the bundle
-- selects the table trivia provider before the source oracle runs.

local bundle, output, mode = ...
assert(bundle and output and (mode == "source" or mode == "image"),
   "usage: lua generate-prelude-image.lua BUNDLE OUTPUT source|image")

assert(loadfile(bundle))()
local roots
if mode == "image" then
   roots = require("nupp.compiler.preludeimage").new()
else
   local envMod = require("nupp.compiler.env")
   local env = envMod.new(".", {
      cache = false,
      memoryOnly = true,
      dialect = "lua51",
      nativeCompilerServices = false,
      config = {_target = {dialect = "lua51"}},
      typeRoots = {},
   })
   roots = {
      annotationsByName = env.annotations.byname,
      featureEffects = env.featureEffects,
      globalTypeDefs = env.globalTypeDefs,
      globalTypes = env.globalTypes,
      globals = env.globals,
      preludeComptimeFunctions = env.preludeComptimeFunctions,
      preludeRuntime = env.preludeRuntime,
      stringLib = env.stringLib,
   }
end

local ids = {}
local tables = {}
local pending = {}
local metatables = {}

local function scalar(value)
   local kind = type(value)
   return kind == "nil" or kind == "boolean" or kind == "number" or kind == "string"
end

local function tableKey(value)
   local parts = {}
   for name, member in pairs(value) do
      if scalar(name) and scalar(member) and member ~= nil then
         parts[#parts + 1] = tostring(name) .. "=" .. tostring(member)
      end
   end
   table.sort(parts)
   assert(#parts > 0, "prelude image has an anonymous table key")
   return table.concat(parts, "|")
end

local function entryKey(key)
   local kind = type(key)
   if kind == "string" then return "1:" .. key end
   if kind == "number" then return "2:" .. string.format("%+.17g", key) end
   if kind == "boolean" then return key and "3:1" or "3:0" end
   if kind == "table" then return "4:" .. tableKey(key) end
   error("prelude image cannot encode a " .. kind .. " table key", 0)
end

local function entries(value)
   local out = {}
   local seenOrder = {}
   for key, child in pairs(value) do
      if key ~= "trivia" then
         if key == "triviaCount" then child = 0 end
         local order = entryKey(key)
         assert(not seenOrder[order], "prelude image has indistinguishable table keys")
         seenOrder[order] = true
         out[#out + 1] = {key = key, value = child, order = order}
      end
   end
   table.sort(out, function(left, right)
      return left.order < right.order
   end)
   return out
end

local function identify(value, path)
   if type(value) ~= "table" or ids[value] then return end
   local id = #tables + 1
   ids[value] = id
   tables[id] = value
   pending[#pending + 1] = value
   local metatable = getmetatable(value)
   if metatable ~= nil then
      metatables[id] = metatable
      identify(metatable, path .. " metatable")
   end
end

for _, name in ipairs({
   "annotationsByName",
   "featureEffects",
   "globalTypeDefs",
   "globalTypes",
   "globals",
   "preludeComptimeFunctions",
   "stringLib",
}) do
   identify(roots[name], name)
end

local at = 1
while at <= #pending do
   local owner = pending[at]
   for _, entry in ipairs(entries(owner)) do
      identify(entry.key, "table " .. ids[owner] .. " key " .. entry.order)
      identify(entry.value, "table " .. ids[owner] .. " value " .. entry.order)
      local keyKind = type(entry.key)
      local valueKind = type(entry.value)
      assert(scalar(entry.key) or keyKind == "table",
         "prelude image cannot encode a " .. keyKind .. " key")
      assert(scalar(entry.value) or valueKind == "table",
         "prelude image cannot encode a " .. valueKind .. " value")
   end
   at = at + 1
end

local file = assert(io.open(output, "wb"))
local function writeValue(value)
   local kind = type(value)
   if kind == "nil" then
      assert(file:write("z"))
   elseif kind == "boolean" then
      assert(file:write(value and "t" or "f"))
   elseif kind == "string" then
      assert(file:write("s", tostring(#value), "\n", value))
   elseif kind == "table" then
      assert(file:write("r", tostring(ids[value]), "\n"))
   elseif kind == "number" then
      local encoded
      if value ~= value then
         encoded = "nan"
      elseif value == math.huge then
         encoded = "inf"
      elseif value == -math.huge then
         encoded = "-inf"
      else
         encoded = string.format("%.17g", value)
      end
      assert(file:write("n", encoded, "\n"))
   else
      error("prelude image cannot encode " .. kind, 0)
   end
end

assert(file:write("NUPP-PRELUDE-1\n", tostring(#tables), "\n"))
for id, value in ipairs(tables) do
   local members = entries(value)
   assert(file:write(tostring(#members), "\n"))
   for _, entry in ipairs(members) do
      writeValue(entry.key)
      writeValue(entry.value)
   end
   assert(file:write(tostring(metatables[id] and ids[metatables[id]] or 0), "\n"))
end
for _, name in ipairs({
   "annotationsByName",
   "featureEffects",
   "globalTypeDefs",
   "globalTypes",
   "globals",
   "preludeComptimeFunctions",
   "stringLib",
}) do
   writeValue(roots[name])
end
writeValue(roots.preludeRuntime)
assert(file:close())

io.stderr:write(("wrote %s with %d tables\n"):format(output, #tables))
