local packs = require("nupp.compiler.build.compilerpacks")
local layouts = require("nupp.compiler.targetlayout")
local hash = require("nupp.compiler.build.hash")
local json = require("testjson")

local M = {}

local function write(path, text)
   local directory = path:match("^(.*)/[^/]+$")
   if directory then os.execute("mkdir -p '" .. directory .. "'") end
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function tool(path, bytes)
   write(path, bytes)
   return {path = path:match("([^/]+)$"), sha256 = hash.sha256(bytes), size = #bytes}
end

function M.resolvesAndAuthenticatesTargetIndexedTools()
   local host = assert(layouts.hostKey())
   local root = os.tmpname()
   os.remove(root)
   local directory = root .. "/" .. host .. "/" .. host
   os.execute("mkdir -p '" .. directory .. "'")
   local cc = tool(directory .. "/cc", "synthetic compiler")
   local ar = tool(directory .. "/ar", "synthetic archiver")
   local linker = tool(directory .. "/host-link", "synthetic host linker")
   write(directory .. "/pack.json", json.encode({
      schemaVersion = 1,
      host = host,
      target = host,
      version = "synthetic-1",
      cc = cc,
      ar = ar,
      linkHost = linker,
      compileFlags = {"--sysroot={pack}/sysroot"},
      linkFlags = {"-L{pack}/lib"},
   }))
   local getenv = os.getenv
   os.getenv = function(name)
      if name == "NUPP_COMPILER_PACK_DIR" then return root end
      return getenv(name)
   end
   local ok, pack, err = pcall(packs.resolve, host)
   os.getenv = getenv
   assert(ok, pack)
   assert(pack, err)
   assert(pack.cc == directory .. "/cc")
   assert(pack.ar == directory .. "/ar")
   assert(pack.linkHost == directory .. "/host-link")
   assert(pack.compileFlags[1] == "--sysroot=" .. directory .. "/sysroot")
   assert(pack.linkFlags[1] == "-L" .. directory .. "/lib")

   write(directory .. "/cc", ("x"):rep(#"synthetic compiler"))
   os.getenv = function(name)
      if name == "NUPP_COMPILER_PACK_DIR" then return root end
      return getenv(name)
   end
   ok, pack, err = pcall(packs.resolve, host)
   os.getenv = getenv
   assert(ok, pack)
   assert(pack == nil and err:find("SHA%-256"), err)
   os.execute("rm -rf '" .. root .. "'")
end

function M.findsPackBesideAnUninstalledReleaseBinary()
   local host = assert(layouts.hostKey())
   local root = os.tmpname()
   os.remove(root)
   local directory = root .. "/lib/nupp/compiler-packs/" .. host .. "/" .. host
   os.execute("mkdir -p '" .. directory .. "'")
   local cc = tool(directory .. "/cc", "release compiler")
   local ar = tool(directory .. "/ar", "release archiver")
   write(directory .. "/pack.json", json.encode({
      schemaVersion = 1,
      host = host,
      target = host,
      version = "release-1",
      cc = cc,
      ar = ar,
   }))
   local getenv = os.getenv
   local oldArg = arg[0]
   os.getenv = function(name)
      if name == "NUPP_COMPILER_PACK_DIR" then return nil end
      return getenv(name)
   end
   arg[0] = root .. "/nupp"
   local ok, pack, err = pcall(packs.resolve, host)
   arg[0] = oldArg
   os.getenv = getenv
   assert(ok, pack)
   assert(pack, err)
   assert(pack.cc == directory .. "/cc")
   os.execute("rm -rf '" .. root .. "'")
end

return M
