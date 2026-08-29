local release = require("nupp.compiler.build.release")
local json = require("testjson")

local function write(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function read(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local function temporaryDirectory()
   local path = os.tmpname()
   os.remove(path)
   assert(os.execute("mkdir -p '" .. path .. "'") == 0)
   return path
end

local function linuxStub()
   return "\127ELF\2" .. ("\0"):rep(13) .. "\62\0"
end

local function macStub()
   return "\207\250\237\254\12\0\0\1"
end

local function windowsStub()
   return "MZ" .. ("\0"):rep(58) .. "\64\0\0\0PE\0\0\100\134"
end

local M = {}

function M.theEmbeddedCatalogIsTheCommittedJsonArtifact()
   local relative = "/build/stub-catalog.json"
   local text = assert(require("nupp.compiler.bundled").source(relative),
      "the compiler carries " .. relative)
   local catalog = json.decode(text)
   assert(catalog.catalogRelease == "development")
   assert(catalog.hostAbi == 1)
   assert(next(catalog.stubs) == nil)

   local getenv = os.getenv
   os.getenv = function(name)
      if name == "NUPP_STUB_CATALOG" then return nil end
      return getenv(name)
   end
   local record, problem = require("nupp.compiler.build.stubs")
      .record("x86_64-unknown-linux-gnu")
   os.getenv = getenv
   assert(not record and problem:find("stub catalog development has no", 1, true),
      "the default catalog is decoded through the production path: " .. tostring(problem))
end

function M.recordsAndVerifiesACompleteStubCatalog()
   local dir = temporaryDirectory()
   local catalogRelease = "release-123"
   local fixtures = {
      {platform = "x86_64-unknown-linux-gnu", artifact = "nupp-host-linux", bytes = linuxStub()},
      {platform = "aarch64-apple-darwin", artifact = "nupp-host-macos", bytes = macStub()},
      {platform = "x86_64-pc-windows-msvc", artifact = "nupp-host-windows.exe", bytes = windowsStub()},
   }
   local records = {}
   for index, fixture in ipairs(fixtures) do
      local artifact = dir .. "/" .. fixture.artifact
      local notices = artifact .. "-notices"
      local record = dir .. "/record-" .. index .. ".json"
      write(artifact, fixture.bytes)
      write(notices, "license text")
      assert(release.record(
         fixture.platform, catalogRelease, artifact, notices, record
      ))
      records[index] = record
   end

   local output = dir .. "/stub-catalog.json"
   assert(release.catalog(catalogRelease, records, dir, output))
   local text = read(output)
   local catalog = json.decode(text)
   assert(catalog.catalogRelease == catalogRelease)
   assert(catalog.hostAbi == 1)
   assert(catalog.stubs["x86_64-unknown-linux-gnu"].artifact == "nupp-host-linux")
   assert(catalog.stubs["aarch64-apple-darwin"].artifact == "nupp-host-macos")
   assert(catalog.stubs["x86_64-pc-windows-msvc"].executableSuffix == ".exe")
   assert(text:find('\n  "catalogRelease":', 1, true),
      "the immutable catalog is stable readable JSON")

   write(dir .. "/nupp-host-linux", linuxStub() .. "damage")
   local verified, problem = release.catalog(catalogRelease, records, dir, output)
   assert(not verified and problem:find("bytes, expected", 1, true),
      "catalog assembly authenticates the downloaded artifact: " .. tostring(problem))
   os.execute("rm -rf '" .. dir .. "'")
end

function M.aRecordRejectsTheWrongExecutableFormat()
   local dir = temporaryDirectory()
   write(dir .. "/notices", "license text")
   write(dir .. "/host", macStub())
   local recorded, problem = release.record(
      "x86_64-unknown-linux-gnu",
      "release-123",
      dir .. "/host",
      dir .. "/notices",
      dir .. "/record.json"
   )
   assert(not recorded and problem:find("not an x86-64 ELF", 1, true),
      "a catalog record cannot mislabel an executable")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.stampsAPortableSourcePayloadIntoAPlatformHost()
   local dir = temporaryDirectory()
   local stub = windowsStub()
   local payload = "return 'portable'\n"
   write(dir .. "/host.exe", stub)
   write(dir .. "/payload.lua", payload)
   assert(release.stampPayload(
      dir .. "/host.exe",
      dir .. "/payload.lua",
      "x86_64-pc-windows-msvc",
      dir .. "/nupp.exe"
   ))
   local stamped = read(dir .. "/nupp.exe")
   assert(stamped:sub(1, #stub) == stub, "stamping retains the native host")
   assert(stamped:sub(#stub + 1, #stub + #payload) == payload,
      "stamping carries the exact source payload")
   assert(stamped:sub(-48, -41) == "NUPPLOAD", "the output has a payload trailer")
   assert(stamped:sub(-36, -33) == "\0\0\0\0",
      "the trailer declares a source payload")
   os.execute("rm -rf '" .. dir .. "'")
end

return M
