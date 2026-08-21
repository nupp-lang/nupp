-- Runs as real source inside the six-library stock Lua 5.1 host. Keep this
-- separate from the C harness so the compiler contract is checked and reviewed
-- as Lua, just like every provider fallback it exercises.

local function noErrors(response, label)
   for _, diagnostic in ipairs(response.diagnostics) do
      assert(diagnostic.severity ~= "error",
         label .. ": " .. diagnostic.code .. ": " .. diagnostic.msg)
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

   local wire = session:request(
      [[{"kind":"check","source":"return 1","options":{"dialect":"lua51"}}]])
   assert(type(wire) == "string" and wire:find("diagnostics", 1, true),
      "JSON request adapter returned no response")

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
