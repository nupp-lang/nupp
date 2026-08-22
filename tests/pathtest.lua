-- `nupp.io.path` through the real provider.
--
-- One table of answers, recorded from the implementation this replaced. A path
-- library's whole job is to agree with everybody else about what a piece of text
-- names, so the useful test is not that each function does something reasonable
-- but that the answers have not moved.
--
-- The distinction the table is really pinning: a path that is *rebuilt* is
-- normalised, and a path that is *sliced* keeps the spelling the caller wrote.
-- Asking for a path's parent asks about that path, not about a tidier one.
local test = require("assert")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.compiler.build.native")

local M = {}

local path, previous, root
local unavailable

local function temporaryRoot()
   local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
   base = base:gsub("\\", "/")
   return (base:gsub("/$", "")) .. "/nupp-path-test-" .. tostring(os.time())
      .. "-" .. tostring(math.random(1, 1e9))
end

function M.beforeAll()
   math.randomseed(os.time())
   root = temporaryRoot()
   os.execute("mkdir -p '" .. root .. "'")
   local libraryPath = os.getenv("NUPP_NATIVE_LIBRARY")
   if not libraryPath then
      local staged, problem = nativeStage.build(root, "out", {["native.path"] = true})
      if not staged then
         unavailable = tostring(problem)
         return
      end
      libraryPath = root .. "/out/lib/nupp_native"
   end
   local library = ("%q"):format(libraryPath)
   local source = stdlib.bootstrap({
      ["native.path"] = true, ["stdlib.io"] = true,
   }):gsub('os%.getenv%("NUPP_NATIVE_LIBRARY"%)', function() return library end)
   previous = rawget(_G, "nupp")
   _G.nupp = nil
   assert(loadstring(source))()
   path = require("nupp.io.path")
end

function M.afterAll()
   if previous ~= nil or rawget(_G, "nupp") ~= nil then
      _G.nupp = previous
   end
   if root then
      os.execute("rm -rf '" .. root .. "'")
   end
end

local function ready()
   if unavailable then
      error("skip: " .. unavailable, 0)
   end
   return path
end

-- A path written the awkward way on purpose: a `.` that normalising removes and
-- slicing keeps, a `..` that cancels a name, and a two-dot extension.
local MESSY = "alpha/./beta/../file.tar.gz"

function M.normalizingResolvesWhatItCanWithoutTheFilesystem()
   local module = ready()
   test.equal(module.newPath(MESSY):normalize():toString(), "alpha/file.tar.gz")
   -- Nothing left means the path described where it already was.
   test.equal(module.newPath("a/.."):normalize():toString(), ".")
   -- A relative path that starts by going up has nowhere to put the answer.
   test.equal(module.newPath("../../a"):normalize():toString(), "../../a")
   -- One at the root has nothing to cancel.
   test.equal(module.newPath("/../a"):normalize():toString(), "/a")
end

function M.readingAPartSlicesRatherThanRebuilds()
   local module = ready()
   local messy = module.newPath(MESSY)
   -- The `./` survives, because this is a question about this path.
   test.equal(messy:parent():toString(), "alpha/./beta/..")
   test.equal(messy:fileName(), "file.tar.gz")
   test.equal(messy:stem(), "file.tar")
   test.equal(messy:extension(), "gz")

   test.equal(module.newPath("/"):parent(), nil, "a root has no parent")
   test.equal(module.newPath("foo"):parent():toString(), "")
   test.equal(module.newPath("/foo"):parent():toString(), "/")
   -- A leading dot is a name, not an extension.
   test.equal(module.newPath(".bashrc"):stem(), ".bashrc")
   test.equal(module.newPath(".bashrc"):extension(), nil)
   test.equal(module.newPath("a."):extension(), "")
   test.equal(module.newPath("noext"):extension(), nil)
   -- `..` is not something a caller could rename.
   test.equal(module.newPath("a/.."):fileName(), nil)
end

function M.derivingReplacesTheNameOrTheExtension()
   local module = ready()
   local messy = module.newPath(MESSY)
   test.equal(messy:withFileName("other.txt"):toString(), "alpha/./beta/../other.txt")
   test.equal(messy:withExtension("bz2"):toString(), "alpha/./beta/../file.tar.bz2")
   test.equal(messy:withExtension(""):toString(), "alpha/./beta/../file.tar")
   -- With no file name there is nothing to drop, so the name is added.
   test.equal(module.newPath("a/.."):withFileName("c"):toString(), "a/../c")
end

-- One anchored and one not do not share a coordinate system. An absolute target
-- is still an answer -- it names where it is without reference to the base --
-- and a relative one against an absolute base is not.
function M.relatingNeedsBothPathsAnchoredTheSameWay()
   local module = ready()
   test.equal(module.newPath("/a/b/c"):relativeTo("/a/d"):toString(), "../b/c")
   test.equal(module.newPath("/a/b"):relativeTo("/a/b"):toString(), "")
   test.equal(module.newPath("/a/b"):relativeTo("a/b"):toString(), "/a/b")
   test.equal(module.newPath("a/b"):relativeTo("/a/b"), nil)
end

function M.joiningLetsAnAbsolutePartReplaceWhatCameBefore()
   local module = ready()
   test.equal(module.newPath("src", "main.nupp"):toString(), "src/main.nupp")
   test.equal(module.newPath("/a", "/b"):toString(), "/b")
   assert(module.newPath("/a"):isAbsolute())
   assert(not module.newPath("a"):isAbsolute())
end

return M
