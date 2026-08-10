-- `nupp.io.files` against a real filesystem, through the real Rust provider.
--
-- The provider is built once for the suite and reached the way a generated
-- program reaches it, so what is proved here is the binding and the ABI rather
-- than a mock of either. Cargo is the one prerequisite; without it the suite
-- skips rather than failing for a reason that is not about files.
local test = require("assert")
local native = require("nupp.compiler.native")
local nativeStage = require("nupp.compiler.build.native")

local M = {}

local root, provider, previous
local unavailable

local function temporaryRoot()
   local base = os.getenv("TMPDIR") or "/tmp"
   return (base:gsub("/$", "")) .. "/nupp-files-test-" .. tostring(os.time())
      .. "-" .. tostring(math.random(1, 1e9))
end

function M.beforeAll()
   math.randomseed(os.time())
   root = temporaryRoot()
   os.execute("mkdir -p '" .. root .. "'")
   local staged, problem = nativeStage.build(root, "out", {["native.files"] = true})
   if not staged then
      unavailable = tostring(problem)
      return
   end
   -- A generated program finds the library beside itself. This chunk is loaded
   -- from a string, so it has no beside; name the staged library outright, which
   -- is the same substitution the NUPP_NATIVE_LIBRARY override performs.
   local library = ("%q"):format(root .. "/out/lib/nupp_native")
   local source = native.bootstrap({["native.files"] = true}):gsub(
      'os%.getenv%("NUPP_NATIVE_LIBRARY"%)', function() return library end)
   previous = rawget(_G, "nupp")
   _G.nupp = nil
   assert(loadstring(source))()
   provider = _G.nupp.io.files
end

function M.afterAll()
   if previous ~= nil or rawget(_G, "nupp") ~= nil then
      _G.nupp = previous
   end
   if root then
      os.execute("chmod -R u+w '" .. root .. "' 2>/dev/null")
      os.execute("rm -rf '" .. root .. "'")
   end
end

local function ready()
   if unavailable then
      test.skip("the files provider did not build: " .. unavailable)
   end
   return provider
end

local function inRoot(name)
   return root .. "/" .. name
end

local function write(path, text)
   local handle = assert(io.open(path, "wb"))
   handle:write(text)
   handle:close()
end

function M.directoriesAreCreatedWithTheirParents()
   local files = ready()
   assert(files.createDirectory(inRoot("a/b/c")))
   assert(files.isDirectory(inRoot("a/b/c")))
   assert(files.isDirectory(inRoot("a")))
   assert(not files.isFile(inRoot("a")))
   assert(files.createDirectory(inRoot("a/b/c")),
      "creating an existing directory succeeds")
end

function M.infoDescribesAFileAndFailsOnAMissingOne()
   local files = ready()
   assert(files.createDirectory(inRoot("info")))
   write(inRoot("info/five.txt"), "hello")
   local info = assert(files.info(inRoot("info/five.txt")))
   test.equal(info.kind, "file")
   test.equal(info.size, 5)
   test.equal(info.readOnly, false)
   assert(info.modified > 1500000000, "a modification time is a Unix timestamp")

   local missing, reason = files.info(inRoot("info/absent"))
   test.equal(missing, nil)
   assert(type(reason) == "string" and #reason > 0,
      "a missing path answers the platform's reason")
   assert(not files.exists(inRoot("info/absent")))
end

function M.symbolicLinksAreCreatedReadAndDistinguished()
   local files = ready()
   assert(files.createDirectory(inRoot("links")))
   write(inRoot("links/target.txt"), "bytes")
   assert(files.createSymlink(inRoot("links/target.txt"), inRoot("links/alias")))

   assert(files.isSymlink(inRoot("links/alias")))
   assert(not files.isSymlink(inRoot("links/target.txt")))
   assert(files.isFile(inRoot("links/alias")), "every other query follows the link")
   test.equal(assert(files.readLink(inRoot("links/alias"))),
      inRoot("links/target.txt"))
   test.equal(assert(files.info(inRoot("links/alias"))).kind, "file")
end

function M.listingDescribesEachChildWithoutFollowingLinks()
   local files = ready()
   assert(files.createDirectory(inRoot("listing/child")))
   write(inRoot("listing/file.txt"), "x")
   assert(files.createSymlink(inRoot("listing/file.txt"), inRoot("listing/alias")))

   local entries = assert(files.list(inRoot("listing")))
   local kinds = {}
   for _, entry in ipairs(entries) do kinds[entry.name] = entry.kind end
   test.equal(#entries, 3)
   test.equal(kinds["child"], "directory")
   test.equal(kinds["file.txt"], "file")
   test.equal(kinds["alias"], "symlink")

   local absent, reason = files.list(inRoot("listing/absent"))
   test.equal(absent, nil)
   assert(type(reason) == "string", "listing a missing directory answers a reason")
end

function M.renamingAndRemovingMoveAndDeletePaths()
   local files = ready()
   assert(files.createDirectory(inRoot("moves/tree/deep")))
   write(inRoot("moves/from.txt"), "content")
   assert(files.rename(inRoot("moves/from.txt"), inRoot("moves/to.txt")))
   assert(files.isFile(inRoot("moves/to.txt")))
   assert(not files.exists(inRoot("moves/from.txt")))

   assert(files.remove(inRoot("moves/to.txt")))
   assert(not files.exists(inRoot("moves/to.txt")))

   local refused, reason = files.remove(inRoot("moves/tree"))
   assert(not refused and type(reason) == "string",
      "removing a populated directory needs the recursive flag")
   assert(files.remove(inRoot("moves/tree"), true))
   assert(not files.exists(inRoot("moves/tree")))
end

function M.readOnlyIsSetAndCleared()
   local files = ready()
   assert(files.createDirectory(inRoot("attributes")))
   write(inRoot("attributes/locked.txt"), "x")
   assert(files.setReadOnly(inRoot("attributes/locked.txt"), true))
   assert(assert(files.info(inRoot("attributes/locked.txt"))).readOnly)
   assert(files.setReadOnly(inRoot("attributes/locked.txt"), false))
   assert(not assert(files.info(inRoot("attributes/locked.txt"))).readOnly)
end

function M.temporariesAreCreatedNotProposed()
   local files = ready()
   assert(files.createDirectory(inRoot("temporary")))
   local file = assert(files.createTemporaryFile({
      directory = inRoot("temporary"), prefix = "unit-", suffix = ".tmp",
   }))
   assert(files.isFile(file), "the temporary file exists when its name is answered")
   assert(file:find("/unit-", 1, true) and file:sub(-4) == ".tmp",
      "the generated name carries the prefix and suffix: " .. file)

   local other = assert(files.createTemporaryFile({directory = inRoot("temporary")}))
   assert(other ~= file, "two temporaries do not collide")

   local directory = assert(files.createTemporaryDirectory({
      directory = inRoot("temporary"),
   }))
   assert(files.isDirectory(directory))

   local absent, reason = files.createTemporaryFile({
      directory = inRoot("temporary/absent"),
   })
   test.equal(absent, nil)
   assert(type(reason) == "string", "an unusable directory answers a reason")
end

function M.pathsAndFoldersAnswerTheEnvironment()
   local files = ready()
   local current = assert(files.currentDirectory())
   assert(files.isDirectory(current), "the working directory is a directory")
   local home = assert(files.userFolder("home"))
   assert(files.isDirectory(home), "the home folder is a directory")
   test.raises(function() files.userFolder("nowhere") end, "no user folder named")
end

function M.argumentsAreCheckedAtTheCallSite()
   local files = ready()
   test.raises(function() files.info(42) end, "must be a path or a string")
   test.raises(function() files.rename(inRoot("a"), true) end,
      "must be a path or a string")
   test.raises(function()
      files.createSymlink(inRoot("a"), inRoot("b"), "sideways")
   end, "symlink kind")
   test.raises(function()
      files.createTemporaryFile({prefix = 7})
   end, "prefix must be a string")
end

function M.aPathObjectIsAcceptedWhereverAStringIs()
   local files = ready()
   local asPath = setmetatable({_text = inRoot("viapath")}, {
      __index = {toString = function(self) return self._text end},
   })
   assert(files.createDirectory(asPath))
   assert(files.isDirectory(inRoot("viapath")))
end

function M.theProviderIsSelectedOnlyByReachingIt()
   local recorded = native.forGlobal("nupp.io.files")
   test.equal(recorded, "native.files")
   local feature = assert(native.feature("native.files"))
   test.equal(feature.cargoFeature, "files")
   test.equal(feature.library, "nupp_native")
   local bootstrap = native.bootstrap({["native.files"] = true})
   assert(bootstrap:find("nuppFilesInfo", 1, true),
      "the files declarations reach a program that uses them")
   assert(not native.bootstrap({["stdlib.io"] = true}):find("nuppFilesInfo", 1, true),
      "a program that does not use them carries none of it")
end

return M
