-- What a stored answer is stamped with, and where it is stored.
--
-- Two facts hold the caches up, and neither shows itself in an answer: a stamp that
-- covers the code the entry came from and no more, and a key that is the same key for
-- callers asking the same question. Getting either wrong costs no correctness -- a miss
-- recomputes -- so nothing else in the suite notices, and the project quietly reparses
-- itself on every command. These are the tests that notice.
local cache = require("nupp.compiler.build.cache")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local ROOT = assert(HERE:match("^(.*)/[^/]+$"), "tests directory has no parent")
local NUPP = ROOT .. "/bin/nupp"

local function tempProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for name, text in pairs(files) do
      local sub = name:match("^(.*)/[^/]+$")
      if sub then
         assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
      end
      local file = assert(io.open(dir .. "/" .. name, "wb"))
      file:write(text)
      file:close()
   end
   return dir
end

local function exists(path)
   local file = io.open(path, "rb")
   if file then
      file:close()
      return true
   end
   return false
end

local M = {}

-- The failure this catches is silent and total: one `require` of a computed name
-- anywhere in the compiler, and every stamp below becomes the whole compiler again.
-- Nothing breaks, every command just goes back to throwing away the last one's work.
function M.eachSubsystemIsStampedWithItselfRatherThanTheWholeCompiler()
   local whole = cache.toolFingerprint()
   local seen = {}
   for _, name in ipairs({
      "nupp.compiler.header",
      "nupp.compiler.fmt",
      "nupp.compiler.check",
      "nupp.compiler.build.modules",
   }) do
      local stamp = cache.subsystemFingerprint({name})
      assert(stamp ~= whole,
         ("%s is stamped with the whole compiler, so the graph could not be read")
         :format(name))
      assert(not seen[stamp],
         ("%s has the same stamp as %s"):format(name, tostring(seen[stamp])))
      seen[stamp] = name
   end
end

-- Falling back is always allowed. It costs work and changes no answer, which is what
-- makes it the right thing to do about a question this cannot answer.
function M.anUnreadableSubsystemFallsBackToTheWholeCompiler()
   assert(cache.subsystemFingerprint({"nupp.compiler.no.such.module"})
      == cache.toolFingerprint(),
      "an unknown module has to leave the stamp covering everything")
end

-- A build adds its generated directory to the include roots and nothing else does.
-- Keyed on the roots, that made every header a build stored a header a check missed.
function M.twoEnvironmentsAgreeOnAHeaderKeyWhenTheModuleNameAgrees()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/m.nupp"] = "local m = {}\nreturn m\n",
   })
   local plain = envMod.new(dir)
   local building = envMod.new(dir, {config = {include = {"src", "build/generated"}}})
   local path = dir .. "/src/m.nupp"
   local text = "local m = {}\nreturn m\n"
   assert(envMod.headerKey(plain, path, text) == envMod.headerKey(building, path, text),
      "a root that changes no module name must not change the key")
   os.execute("rm -rf '" .. dir .. "'")
end

-- The prelude is the compiler's own source and is checked before the project has been
-- looked at. Answering its lookups from the project made every environment -- one per
-- case in the suites that check fragments -- read and index every file in the project.
function M.makingAnEnvironmentDoesNotReadTheProject()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" } }\n',
      ["src/m.nupp"] = "local m = {}\nreturn m\n",
   })
   local env = envMod.new(dir)
   assert(env.projectIndex == nil,
      "the prelude bootstrap built the project index")
   assert(env.bootstrapping == nil,
      "the bootstrap flag outlived the bootstrap")
   local index = envMod.ensureProjectIndex(env)
   assert(env.projectIndex ~= nil and index == env.projectIndex,
      "and asking for it still builds it")
   os.execute("rm -rf '" .. dir .. "'")
end

-- Content-keyed stores move; the build state does not.
function M.namedCacheDirectoryHoldsTheStoresThatAnswerAboutContent()
   local dir = tempProject({
      ["nupp.lua"] = 'return { include = { "src" }, build = { entries = { "m" } } }\n',
      ["src/m.nupp"] = "local m = {}\nreturn m\n",
   })
   local shared = tempProject({})
   local status = os.execute(("cd '%s' && NUPP_CACHE_DIR='%s' '%s' check > /dev/null 2>&1")
      :format(dir, shared, NUPP))
   assert(status == 0, "the check itself has to pass")
   assert(exists(shared .. "/headers.buf"),
      "headers were not stored where NUPP_CACHE_DIR named")
   assert(not exists(dir .. "/build/cache/headers.buf"),
      "headers were also stored in the project, which is the directory being replaced")
   assert(exists(dir .. "/build/cache/checks.buf"),
      "the check state is keyed by module name and stays with the project")
   os.execute("rm -rf '" .. dir .. "' '" .. shared .. "'")
end

return M
