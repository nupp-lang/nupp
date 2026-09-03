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
local native = require("nupp.compiler.native")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.compiler.build.native")
local pathtext = require("nupp.io.pathtext")

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
   local libraryPath = os.getenv("NUPP_NATIVE_V2_LIBRARY")
   if not libraryPath then
      local staged, problem = nativeStage.build(root, "out", {["native.path"] = true})
      if not staged then
         unavailable = tostring(problem)
         return
      end
      libraryPath = root .. "/out/lib/nupp_native_v2"
   end
   local library = ("%q"):format(libraryPath)
   local source = stdlib.bootstrap({
      ["native.path"] = true, ["stdlib.io"] = true,
   }):gsub('os%.getenv%("NUPP_NATIVE_V2_LIBRARY"%)', function() return library end)
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
   test.equal(module.newPath("/a/b"):relativeTo("a/b"):toString(), "/a/b")
   test.equal(module.newPath("a/b"):relativeTo("/a/b"), nil)
end

-- A path expressed against itself is where the base already is, and `.` is
-- how a path spells that: `""` names nothing a filesystem call accepts.
function M.relatingAPathToItselfAnswersDot()
   local module = ready()
   test.equal(module.newPath("/a/b"):relativeTo("/a/b"):toString(), ".")
   test.equal(module.newPath("a/b"):relativeTo("a/b"):toString(), ".")
   -- Nor does a trailing separator or a `.` component move the answer.
   test.equal(module.newPath("a/b/"):relativeTo("a/b"):toString(), ".")
   test.equal(module.newPath("a/./b"):relativeTo("a/b"):toString(), ".")
end

function M.joiningLetsAnAbsolutePartReplaceWhatCameBefore()
   local module = ready()
   test.equal(module.newPath("src", "main.nupp"):toString(), "src/main.nupp")
   test.equal(module.newPath("/a", "/b"):toString(), "/b")
   assert(module.newPath("/a"):isAbsolute())
   assert(not module.newPath("a"):isAbsolute())
end

function M.filesystemQuestionsUseTheGenericProvider()
   local module = ready()
   local current = assert(module.currentDirectory())
   assert(current:isAbsolute())
   test.equal(assert(module.newPath("."):absolute()):toString(), current:toString())
   test.equal(assert(module.newPath("alpha//./beta/.."):absolute()):toString(),
      current:join("alpha/beta/.."):toString())

   local canonical = assert(module.newPath(root):canonicalize())
   assert(canonical:isAbsolute())
   test.equal(assert(canonical:canonicalize()):toString(), canonical:toString())
end

function M.pathStagesOnlyTheGenericFilesystemSlice()
   local feature = assert(native.feature("native.path"))
   test.equal(feature.providerFeature, "filesystem")
   test.equal(feature.providerDriver, "native-rust")
   test.equal(feature.provider, "nupp_native_v2")
   test.equal(feature.host, "native-files")
   test.equal(feature.library, "nupp_native_v2")
   test.equal(feature.runtimeModule, "nupp.io.path.provider")
   test.equal(table.concat(feature.requires or {}, ","),
      "runtime.path,runtime.native_v2")
   local runtime = assert(native.feature("runtime.path"))
   test.equal(runtime.runtimeModule, "nupp.io.path")
   test.equal(runtime.portableRuntime, true)
   local handle = io.open("runtime/native/c/path.c", "rb")
   if handle then
      handle:close()
      error("the removed path provider still exists")
   end
   local source = assert(io.open("src/nupp/io/path/init.nupp", "rb"))
   local text = source:read("*a")
   source:close()
   assert(not text:find("nupp.runtime.native", 1, true),
      "the shared path implementation has no provider dependency")
   local provider = assert(io.open("src/nupp/io/path/provider.nupp", "rb"))
   local providerText = provider:read("*a")
   provider:close()
   assert(providerText:find("nupp.runtime.native", 1, true),
      "the host path seam loads the ABI-v2 provider")
   assert(providerText:find("nuppNativeV2Files", 1, true),
      "the host path seam declares the Rust filesystem ABI it calls")
end

-- The scalar rules take the spelling convention as data, so both platforms are
-- testable on one machine. These are Windows answers even on a POSIX runner.
function M.windowsTextRulesArePlatformIndependent()
   assert(pathtext.isAbsolute("C:\\alpha", true))
   assert(not pathtext.isAbsolute("C:alpha", true))
   assert(pathtext.isAbsolute("\\alpha", true))
   test.equal(pathtext.normalize("C:\\alpha\\.\\beta\\..\\file.txt", true),
      "C:/alpha/file.txt")
   test.equal(pathtext.normalize("C:alpha\\..\\beta", true), "C:beta")
   test.equal(pathtext.part("C:\\alpha\\.\\beta\\..\\file.tar.gz", 0, true),
      "C:/alpha/./beta/..")
   test.equal(pathtext.part("C:\\alpha\\file.tar.gz", 3, true), "gz")
   test.equal(pathtext.join({"C:\\alpha", "\\beta"}, true), "C:/beta")
   test.equal(pathtext.join({"C:\\alpha", "D:\\beta"}, true), "D:/beta")
   test.equal(pathtext.clean("C:\\alpha\\.\\\\beta\\..", true),
      "C:/alpha/beta/..")
   test.equal(assert(pathtext.relative("C:\\alpha\\beta", "C:\\alpha\\other", true)),
      "../beta")
   test.equal(pathtext.with("C:\\alpha\\file.txt", "bak", true, true),
      "C:/alpha/file.bak")
end

-- An anchor is compared by what it is rather than how it is spelled: `/` and
-- `\` name the same root, while two drives are two coordinate systems and no
-- count of `..` steps leads from one to the other.
function M.relatingWindowsPathsComparesAnchorsByKind()
   local answer, reason = pathtext.relative("C:\\a", "D:\\b", true)
   test.equal(answer, nil)
   assert(type(reason) == "string" and #reason > 0,
      "two drives answer why there is no relative form")
   test.equal(assert(pathtext.relative("C:/a", "C:\\b", true)), "../a")
   test.equal(assert(pathtext.relative("\\a", "/b", true)), "../a")
   -- A drive-anchored target against a merely rooted base is the same refusal.
   test.equal(pathtext.relative("C:\\a", "\\b", true), nil)
end

-- A bare drive prefix names a coordinate system rather than a place, so joining
-- onto one stays drive-relative. A share root is a place, and keeps its
-- separator.
function M.joiningOntoABareDriveStaysDriveRelative()
   test.equal(pathtext.pushPart("C:", "foo", true), "C:foo")
   test.equal(pathtext.join({"C:", "foo"}, true), "C:foo")
   test.equal(pathtext.join({"\\\\server\\share", "file"}, true),
      "//server/share/file")
end

-- The verbatim form's whole point is that the system does not normalise it,
-- so nothing here may either: no `..` resolution, no separator respelling.
-- The system reads `\\?\` and nothing else -- not `//?/`, and not `/` as a
-- separator after it -- so a rewritten answer names a different thing.
function M.verbatimWindowsPathsAreCarriedUntouched()
   test.equal(pathtext.normalize("\\\\?\\C:\\a\\..\\b", true),
      "\\\\?\\C:\\a\\..\\b")
   test.equal(pathtext.normalize("\\\\?\\UNC\\server\\share\\a\\..\\b", true),
      "\\\\?\\UNC\\server\\share\\a\\..\\b")
   test.equal(pathtext.clean("\\\\?\\C:\\a\\.\\\\b", true),
      "\\\\?\\C:\\a\\.\\\\b")
   test.equal(pathtext.finish("\\\\?\\C:\\a", true), "\\\\?\\C:\\a")
   -- Joining appends the one separator the system reads there.
   test.equal(pathtext.pushPart("\\\\?\\C:\\a", "b", true), "\\\\?\\C:\\a\\b")
   test.equal(pathtext.with("\\\\?\\C:\\a\\file.txt", "bak", true, true),
      "\\\\?\\C:\\a\\file.bak")
   -- Expressing one is exactly the component reasoning verbatim opts out of.
   local answer, reason = pathtext.relative("\\\\?\\C:\\a\\b", "\\\\?\\C:\\a", true)
   test.equal(answer, nil)
   assert(type(reason) == "string" and #reason > 0,
      "a verbatim path answers why there is no relative form")
end

return M
