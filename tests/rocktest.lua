local rock = require("nupp.compiler.rock")

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

function M.initCreatesTheTypedRockContract()
   local dir = tempDirectory()
   local ok, err = rock.init("sample-rock", dir)
   assert(ok, err)
   assert(exists(dir .. "/nupp.lua"), "the project manifest was written")
   assert(exists(dir .. "/src/sample_rock.nupp"), "the runtime source was written")
   assert(exists(dir .. "/nupp/sample_rock.d.nupp"),
      "the matching declaration was written")
   assert(exists(dir .. "/sample-rock-dev-1.rockspec"), "the rockspec was written")
   local again, againErr = rock.init("sample-rock", dir)
   assertEq(again, nil, "init refuses to overwrite its directory")
   assert(againErr:find("already exists", 1, true), againErr)
   remove(dir)
end

function M.packAndTestAProjectFromACleanRockTree()
   local dir = tempDirectory()
   local ok, err = rock.init("sample-rock", dir)
   assert(ok, err)
   local packed, packErr = rock.pack(dir)
   assert(packed, packErr)
   assert(exists(packed), "pack wrote the rock LuaRocks named")
   local checked, checkErr = rock.test(dir)
   assert(checked, checkErr)
   assertEq(checked, packed, "the clean consumer checked the packed artifact")
   remove(dir)
end

return M
