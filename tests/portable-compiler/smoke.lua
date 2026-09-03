-- Runs as real source inside the six-library stock Lua 5.1 host. Keep this
-- separate from the C harness so the compiler contract is checked and reviewed
-- as Lua, just like every provider fallback it exercises.

local function noErrors(response, label)
   for _, diagnostic in ipairs(response.diagnostics) do
      assert(diagnostic.severity ~= "error",
         label .. ": " .. diagnostic.code .. ": " .. diagnostic.msg)
   end
end

local function equivalent(got, want, path)
   if type(got) ~= type(want) then
      error(path .. " has type " .. type(got) .. ", expected " .. type(want), 0)
   end
   if type(got) ~= "table" then
      assert(got == want, path .. " differs: " .. tostring(got) .. " ~= " .. tostring(want))
      return
   end
   for key, value in pairs(want) do
      equivalent(got[key], value, path .. "." .. tostring(key))
   end
   for key in pairs(got) do
      assert(want[key] ~= nil, path .. " has unexpected member " .. tostring(key))
   end
end

return function(Browser)
   local session = Browser.new()
   local source = "local answer: integer = 42\nreturn answer"

   local checked = session:check(source, "playground.nupp", {
      strict = true,
      dialect = "lua51",
   })
   noErrors(checked, "Lua 5.1 check")

   local compiled = session:compile(source, "playground.nupp", {
      strict = true,
      optimize = true,
      dialect = "lua51",
   })
   noErrors(compiled, "Lua 5.1 compile")
   assert(type(compiled.code) == "string" and #compiled.code > 0,
      "Lua 5.1 compile returned no source")
   assert(loadstring(compiled.code, "@generated-lua51"),
      "stock Lua 5.1 cannot parse generated Lua 5.1")

   local hover = session:hover(7)
   assert(hover.found and hover.name == "answer", "hover did not reuse the last check")

   local native = session:compile("const value = 2ULL\nreturn value",
      "playground.nupp", {dialect = "luajit"})
   noErrors(native, "LuaJIT compile")
   assert(native.code and native.code:find("2ULL", 1, true),
      "LuaJIT-only literal did not survive generation")
   for _, diagnostic in ipairs(native.diagnostics) do
      assert(diagnostic.code ~= "NUPP3005",
         "the Lua 5.1 host falsely parsed LuaJIT output")
   end

   local browserSource = [[
local crypto = require("nupp.browser.crypto")
local storage = require("nupp.browser.storage")
local time = require("nupp.time")
local hash = require("nupp.data.hash")
time.sleep(1)
storage.set("key", crypto.sha256(crypto.randomBytes(16)))
print(storage.get("key"), hash.hmacHex("key", "message"), crypto.uuid4())
]]
   local browser = session:compile(browserSource, "browser-platform.nupp", {
      strict = true,
      dialect = "lua51",
   })
   noErrors(browser, "browser platform compile")
   assert(type(browser.code) == "string" and #browser.code > 0,
      "browser platform compile returned no source")

   local browserGpu = session:compile([[
local gpu = require("nupp.browser.gpu")
local u32 = nupp.math.u32.wrap
local values: {uint32} = {u32(0), u32(1)}
local result = gpu.xorU32(values, u32(0xa5a5a5a5))
print(result[1], result[2])
]], "webgpu-compute.nupp", {
      strict = true,
      dialect = "lua51",
   })
   noErrors(browserGpu, "browser WebGPU compile")
   assert(type(browserGpu.code) == "string" and #browserGpu.code > 0,
      "browser WebGPU compile returned no source")

   local wire = session:request(
      [[{"kind":"check","source":"return 1","options":{"dialect":"lua51"}}]])
   assert(type(wire) == "string" and wire:find("diagnostics", 1, true),
      "JSON request adapter returned no response")

   if NUPP_EXPECTED then
      local json = require("nupp.runtime.provider.lunajson")
      local expected = json.decode(NUPP_EXPECTED, json.NULL)
      local differentialSource = "local answer: integer = 42\nreturn answer"
      local portable = {
         check = session:check(differentialSource, "differential.nupp", {
            strict = true,
            dialect = "lua51",
         }),
         compile = session:compile(differentialSource, "differential.nupp", {
            strict = true,
            optimize = true,
            dialect = "lua51",
         }),
         hover = session:hover(7),
      }
      equivalent(portable, expected, "native-versus-portable corpus")
   end

   local forbidden = {
      ffi = true,
      jit = true,
      lpeg = true,
      re = true,
      ["nupp.compiler.fs"] = true,
      ["nupp.compiler.build.store"] = true,
      ["nupp.compiler.comptimeworker"] = true,
      ["nupp.io.files"] = true,
      ["nupp.io.process"] = true,
   }
   for _, name in ipairs(NUPP_REQUIRED) do
      assert(not forbidden[name], "portable compiler loaded forbidden module " .. name)
      assert(package.loaded[name] ~= nil or package.preload[name] ~= nil,
         "required module was not packaged: " .. name)
   end
end
