local rock = require("nupp.compiler.rock")
local template = require("nupp.compiler.template")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function exists(path)
   local file = io.open(path, "rb")
   if not file then return false end
   file:close()
   return true
end

local function tempDirectory()
   local dir = os.tmpname()
   os.remove(dir)
   return dir
end

local function remove(dir)
   os.execute("rm -rf '" .. dir .. "'")
end

local M = {}

-- What `nupp init lib` writes, which is the layout pack and test are about.
local function scaffold(name, dir)
   local source = assert(template.resolve("lib"))
   local plan = assert(template.plan(source, dir, { name = name }))
   assert(template.write(plan))
end

function M.theLibTemplateWritesTheTypedRockContract()
   local dir = tempDirectory()
   scaffold("sample-rock", dir)
   assert(exists(dir .. "/nupp.lua"), "the project manifest was written")
   assert(exists(dir .. "/src/samplerock.nupp"), "the runtime source was written")
   assert(exists(dir .. "/nupp/samplerock.d.nupp"),
      "the matching declaration was written")
   assert(exists(dir .. "/sample-rock-dev-1.rockspec"), "the rockspec was written")
   remove(dir)
end

function M.packAndTestAProjectFromACleanRockTree()
   local dir = tempDirectory()
   scaffold("sample-rock", dir)
   local packed, packErr = rock.pack(dir)
   assert(packed, packErr)
   assert(exists(packed), "pack wrote the rock LuaRocks named")
   local checked, checkErr = rock.test(dir)
   assert(checked, checkErr)
   assertEq(checked, packed, "the clean consumer checked the packed artifact")
   remove(dir)
end

return M
