-- The scaffolder: what a TEMPLATE argument means, what substitution does, what
-- the sandbox refuses, and what never reaches the disk.
--
-- The acceptance tests at the bottom are the ones that keep a built-in template
-- from rotting: they scaffold it and then hold the result to `check`, `build`,
-- `test` and `run`, which is the promise `nupp init` makes and the one a reader
-- tests first.
local template = require("nupp.compiler.template")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pipe = assert(io.popen("pwd"))
   HERE = pipe:read("*l") .. "/" .. HERE
   pipe:close()
end
local ROOT = HERE .. "/.."
local NUPP = os.getenv("NUPP_TEST_BIN") or ROOT .. "/bin/nupp"

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

local function write(path, text)
   os.execute("mkdir -p '" .. path:match("^(.*)/[^/]+$") .. "'")
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function tempDirectory()
   local dir = os.tmpname()
   os.remove(dir)
   return dir
end

local function remove(dir)
   os.execute("rm -rf '" .. dir .. "'")
end

local function shell(command)
   local pipe = assert(io.popen(command .. " 2>&1"))
   local out = pipe:read("*a")
   local ok = pipe:close()
   return ok and true or false, out
end

-- A template on disk, from a table of relative path to contents.
local function templateDirectory(files)
   local dir = tempDirectory()
   for path, text in pairs(files) do
      write(dir .. "/" .. path, text)
   end
   return dir
end

local M = {}

-- Resolution ---------------------------------------------------------------

function M.aBareNameIsABuiltIn()
   local source = assert(template.resolve("app"))
   assertEq(source.kind, "builtin", "app is a built-in")
   assertEq(source.name, "app", "and keeps its name")
end

function M.noArgumentIsTheDefaultTemplate()
   local source = assert(template.resolve(nil))
   assertEq(source.kind, "builtin", "the default is a built-in")
   assertEq(source.name, "app", "and it is app")
end

function M.anUnknownBareNameNamesTheBuiltInsRatherThanGuessing()
   local source, err = template.resolve("nosuchtemplate")
   assertEq(source, nil, "an unknown name resolves to nothing")
   assert(err:find("no built-in template is called", 1, true), err)
   assert(err:find("app", 1, true), "the complaint lists what there is: " .. err)
end

function M.aLeadingDotOrSlashIsADirectory()
   for _, spelling in ipairs({"./here", "../there", "/abs/path"}) do
      local source = assert(template.resolve(spelling))
      assertEq(source.kind, "directory", spelling .. " is a directory")
   end
end

function M.ownerRepoIsGitHub()
   local source = assert(template.resolve("nupp-lang/templates"))
   assertEq(source.kind, "remote", "owner/repo is remote")
   assertEq(source.url, "https://github.com/nupp-lang/templates", "expanded to GitHub")
   assertEq(source.subdir, nil, "with no subdirectory")
end

function M.ownerRepoCarriesASubdirectoryAndARevision()
   local source = assert(template.resolve("tecs-engine/tecs/templates/game@v2.0"))
   assertEq(source.url, "https://github.com/tecs-engine/tecs", "the repository")
   assertEq(source.subdir, "templates/game", "the path within it")
   assertEq(source.rev, "v2.0", "the revision")
end

function M.aFullUrlIsUsedAsGiven()
   local source = assert(template.resolve("git@github.com:owner/repo.git"))
   assertEq(source.kind, "remote", "an ssh spelling is remote")
   assertEq(source.url, "git@github.com:owner/repo.git", "and is not rewritten")
   -- An `@` is ordinary punctuation in a URL, so it is not read as a revision.
   assertEq(source.rev, nil, "the @ in the URL is not a revision")
end

function M.aRevisionGivenTwiceIsRefused()
   local source, err = template.resolve("owner/repo@v1", nil, "v2")
   assertEq(source, nil, "two revisions resolve to nothing")
   assert(err:find("given twice", 1, true), err)
end

function M.fromRefusesATemplateArgumentAndARevision()
   local _, both = template.resolve("app", "/some/dir")
   assert(both:find("one too many", 1, true), both)
   local _, rev = template.resolve(nil, "/some/dir", "v1")
   assert(rev:find("no meaning", 1, true), rev)
end

function M.aBuiltInHasNoRevisions()
   local source, err = template.resolve("app", nil, "v1")
   assertEq(source, nil, "a pinned built-in resolves to nothing")
   assert(err:find("no revisions", 1, true), err)
end

-- Substitution --------------------------------------------------------------

function M.substitutionFillsDeclaredNames()
   local got = assert(template.substitute("${a}-${b}", {a = "one", b = "two"}, "x"))
   assertEq(got, "one-two", "both names were filled")
end

function M.aDoubledDollarIsALiteralOpener()
   local got = assert(template.substitute("$${name} and ${name}", {name = "x"}, "y"))
   assertEq(got, "${name} and x", "the escape is not re-read as an opener")
end

function M.anUndeclaredNameIsRefusedWithItsFile()
   local got, err = template.substitute("${nope}", {name = "x"}, "src/main.nupp")
   assertEq(got, nil, "an undeclared name substitutes to nothing")
   assert(err:find("src/main.nupp", 1, true), err)
   assert(err:find("${nope}", 1, true), err)
end

-- The template manifest and its sandbox -------------------------------------

function M.aManifestDeclaresVariablesWithPatterns()
   local manifest = assert(template.manifest([[
      return {description = "d", variables = {who = {default = "world"}}}
   ]], "template.lua"))
   assertEq(manifest.description, "d", "the description came through")
   assertEq(manifest.variables.who.default, "world", "and the default")
end

function M.theSandboxRefusesEveryWayOut()
   local reaches = {
      io = [[return {description = io.open("/etc/passwd") and "x"}]],
      os = [[return {description = tostring(os.execute("true"))}]],
      require = [[require("nupp.compiler.fs") return {}]],
      loadstring = [[loadstring("return 1") return {}]],
      package = [[return {description = tostring(package.path)}]],
   }
   for name, text in pairs(reaches) do
      local manifest, err = template.manifest(text, "template.lua")
      assertEq(manifest, nil, name .. " is not reachable from a template")
      assert(err, "and the refusal says so for " .. name)
   end
end

function M.aTemplateThatLoopsIsRefusedRatherThanWaitedFor()
   local manifest, err = template.manifest("while true do end", "template.lua")
   assertEq(manifest, nil, "a loop returns no manifest")
   assert(err:find("too long", 1, true), err)
end

function M.anUnknownFieldIsRefusedByName()
   local _, err = template.manifest([[return {hooks = {"rm -rf /"}}]], "template.lua")
   assert(err:find("hooks", 1, true), err)
   assert(err:find("not a template field", 1, true), err)
end

function M.anUnknownStepIsRefusedWithTheStepsThereAre()
   local _, err = template.manifest([[return {after = {"deploy"}}]], "template.lua")
   assert(err:find("deploy", 1, true), err)
   assert(err:find("build", 1, true), "the complaint lists the steps: " .. err)
end

function M.derivedVariablesCannotBeDeclared()
   local _, err = template.manifest([[return {variables = {moduleName = {}}}]], "template.lua")
   assert(err:find("derived", 1, true), err)
end

function M.nameCannotBeGivenADefault()
   local _, err = template.manifest(
      [[return {variables = {name = {default = "x"}}}]], "template.lua")
   assert(err:find("cannot have a default", 1, true), err)
end

-- Variable values -----------------------------------------------------------

function M.aDeclaredPatternIsEnforcedInTheTemplatesOwnWords()
   local manifest = assert(template.manifest([[
      return {variables = {name = {pattern = "^[a-z]+$", invalid = "lowercase only, please"}}}
   ]], "template.lua"))
   local values, err = template.values(manifest, "Not Lower", "d")
   assertEq(values, nil, "a value outside the pattern is refused")
   assertEq(err, "lowercase only, please", "in the template's own sentence")
   assert(template.values(manifest, "fine", "d"), "and a matching one is not")
end

function M.moduleNameIsTheProjectNameInLuacase()
   local manifest = assert(template.manifest("return {}", "template.lua"))
   local values = assert(template.values(manifest, "my-lib", "somewhere/my-lib"))
   assertEq(values.name, "my-lib", "the name is as given")
   assertEq(values.moduleName, "mylib", "the module name is canonical luacase")
   assertEq(values.directory, "somewhere/my-lib", "the directory is the destination")
end

function M.settingADerivedNameIsRefusedRatherThanIgnored()
   local manifest = assert(template.manifest("return {}", "template.lua"))
   local _, err = template.values(manifest, "x", "d", {name = "other"})
   assert(err:find("derived from the project name", 1, true), err)
end

function M.aRequiredVariableWithNoValueSaysWhatItIsFor()
   local manifest = assert(template.manifest([[
      return {variables = {author = {required = true, description = "who wrote it"}}}
   ]], "template.lua"))
   local _, err = template.values(manifest, "x", "d")
   assert(err:find("who wrote it", 1, true), err)
   assert(err:find("--set author=", 1, true), err)
end

-- Reading a tree ------------------------------------------------------------

function M.gitDirectoriesArePrunedAtEveryDepth()
   local dir = templateDirectory({
      ["template.lua"] = "return {}",
      ["keep.txt"] = "kept",
      [".git/config"] = "[core]",
      ["vendor/.git/config"] = "[core]",
      [".gitignore"] = "/build/",
   })
   local into = tempDirectory()
   local plan = assert(template.plan({kind = "directory", path = dir}, into))
   local seen = {}
   for _, file in ipairs(plan.files) do seen[file.output] = true end
   assert(seen["keep.txt"], "an ordinary file is carried")
   assert(seen[".gitignore"], "a .gitignore is carried, being a project file")
   assert(not seen[".git/config"], "the root repository store is pruned")
   assert(not seen["vendor/.git/config"], "and so is a nested one")
   remove(dir)
end

function M.aSymlinkIsReportedRatherThanFollowed()
   local dir = templateDirectory({["template.lua"] = "return {}", ["real.txt"] = "x"})
   os.execute("ln -s /etc/passwd '" .. dir .. "/link.txt'")

   -- Windows has no unprivileged symbolic link, and `ln -s` there copies the
   -- target rather than failing. That leaves an ordinary file, which the walk
   -- is right to carry -- so the case this names cannot be built there, and
   -- asserting on it would be asserting on the copy.
   local linked = false
   for _, entry in ipairs(assert(require("nupp.io.files").list(dir))) do
      linked = linked or (entry.name == "link.txt" and entry.kind == "symlink")
   end
   if not linked then
      remove(dir)
      return require("assert").skip("this platform has no unprivileged symbolic link")
   end

   local into = tempDirectory()
   local plan, err = template.plan({kind = "directory", path = dir}, into)
   assertEq(plan, nil, "a tree holding a link produces no plan")
   assert(err:find("symbolic link", 1, true), err)
   assert(not exists(into), "and nothing was written")
   remove(dir)
end

function M.aDirectoryWithoutATemplateManifestIsNotATemplate()
   local dir = templateDirectory({["some.txt"] = "x"})
   local plan, err = template.plan({kind = "directory", path = dir}, tempDirectory())
   assertEq(plan, nil, "no manifest, no plan")
   assert(err:find("template.lua", 1, true), err)
   remove(dir)
end

-- Refusals before writing ---------------------------------------------------

local function planRefuses(files, label, needle, name)
   local dir = templateDirectory(files)
   local into = tempDirectory()
   local plan, err = template.plan({kind = "directory", path = dir}, into, {name = name})
   assertEq(plan, nil, label)
   assert(err:find(needle, 1, true), err)
   assert(not exists(into), "and the destination was left alone")
   remove(dir)
end

function M.aPathLeavingTheDestinationIsRefused()
   -- A bare `..` carries no separator, so it gets past the value check and is
   -- caught by the path check. Both refusals are wanted; this is the one that
   -- only the assembled path can see.
   planRefuses({
      ["template.lua"] = [[return {variables = {up = {default = ".."}}}]],
      ["${up}/escaped.txt"] = "x",
   }, "an escaping path produces no plan", "leaves the destination")
end

function M.aValueHoldingASeparatorIsRefusedByName()
   planRefuses({
      ["template.lua"] = [[return {variables = {sub = {default = "a/b"}}}]],
      ["${sub}.txt"] = "x",
   }, "a separator in a value produces no plan", "may not contain a path separator")
end

function M.twoFilesBecomingOnePathIsRefused()
   planRefuses({
      ["template.lua"] = [[return {variables = {a = {default = "same"}}}]],
      ["${a}.txt"] = "one",
      ["same.txt"] = "two",
   }, "a collision produces no plan", "both become")
end

function M.theTwoDestinationPoliciesDisagreeAboutAnEmptyDirectory()
   local dir = templateDirectory({["template.lua"] = "return {}", ["a.txt"] = "x"})
   local source = {kind = "directory", path = dir}

   local empty = tempDirectory()
   os.execute("mkdir -p '" .. empty .. "'")
   assert(template.plan(source, empty, {policy = "emptyOrGitOnly"}),
      "init accepts a directory somebody has already made")
   local refused, err = template.plan(source, empty, {policy = "absent"})
   assertEq(refused, nil, "rock init does not")
   assert(err:find("already exists", 1, true), err)

   local withGit = tempDirectory()
   os.execute("mkdir -p '" .. withGit .. "/.git'")
   assert(template.plan(source, withGit, {policy = "emptyOrGitOnly"}),
      "a directory holding only .git is the ordinary case")

   local occupied = tempDirectory()
   os.execute("mkdir -p '" .. occupied .. "'")
   write(occupied .. "/something.txt", "x")
   local no, occupiedErr = template.plan(source, occupied, {policy = "emptyOrGitOnly"})
   assertEq(no, nil, "a directory with a file in it is refused")
   assert(occupiedErr:find("not empty", 1, true), occupiedErr)

   remove(dir) remove(empty) remove(withGit) remove(occupied)
end

-- The built-in templates ----------------------------------------------------

function M.everyBuiltInTemplateFileIsStagedByTheManifest()
   -- The resource list in nupp.lua is written by hand, and a template file added
   -- without a line there is one every released binary quietly lacks. This is
   -- the check that turns that into a failure here instead.
   local manifest = assert(loadfile(ROOT .. "/nupp.lua"))()
   local staged = {}
   for _, target in pairs(manifest.build.targets) do
      for _, resource in ipairs(target.resources or {}) do
         if type(resource) == "table" and resource.source:match("^templates/") then
            staged[resource.source] = true
         end
      end
   end
   local _, listing = shell("find '" .. ROOT .. "/templates' -type f")
   local missing = {}
   for path in listing:gmatch("[^\n]+") do
      local relative = path:sub(#ROOT + 2)
      if not staged[relative] then missing[#missing + 1] = relative end
   end
   assertEq(#missing, 0,
      "template files missing from the resource list in nupp.lua:\n  "
      .. table.concat(missing, "\n  "))
end

function M.theBuiltInsAreTheTemplatesThatAreThere()
   local names = template.builtins()
   assertEq(#names, 3, "three built-ins ship")
   assertEq(names[1], "app", "app is one")
   assertEq(names[2], "lib", "lib is one")
   assertEq(names[3], "love", "and love is the other")
   assert(#template.builtinDescription("app") > 0, "each says what it is for")
end

function M.aBuiltInReadsTheSameFromTheCarriedTreeAsFromTheDirectory()
   -- The equivalence the whole design rests on: what a built-in scaffolds and
   -- what the same directory scaffolds through --from are the same bytes.
   local carried = tempDirectory()
   local fromDisk = tempDirectory()
   assert(template.write(assert(template.plan(
      assert(template.resolve("lib")), carried, {name = "sample"}))))
   assert(template.write(assert(template.plan(
      {kind = "directory", path = ROOT .. "/templates/lib"}, fromDisk, {name = "sample"}))))
   local _, diff = shell("diff -r '" .. carried .. "' '" .. fromDisk .. "'")
   assertEq(diff, "", "the carried tree and the directory scaffold identically")
   remove(carried) remove(fromDisk)
end

-- Remote templates ----------------------------------------------------------
--
-- Served over `file://` from a repository made here, so the suite needs no
-- network and still exercises the clone, the commit resolution and the
-- subdirectory.

local function repository(files)
   local dir = templateDirectory(files)
   assert(shell("cd '" .. dir .. "' && git init -q . && git add -A"
      .. " && git -c user.email=t@t -c user.name=t commit -qm fixture"))
   return dir, "file://" .. dir
end

function M.aRemoteScaffoldsIdenticallyToTheSameTreeOnDisk()
   local dir, url = repository({
      ["template.lua"] = [[return {variables = {who = {default = "world"}}}]],
      ["src/main.nupp"] = 'print("hello ${who} from ${name}")',
      [".gitignore"] = "/build/",
   })
   local fromDisk = tempDirectory()
   assert(template.write(assert(template.plan(
      {kind = "directory", path = dir}, fromDisk, {name = "sample"}))))

   local scratch = tempDirectory()
   os.execute("mkdir -p '" .. scratch .. "'")
   local source = assert(template.resolve(url))
   assert(template.fetch(source, scratch))
   assert(source.commit and #source.commit == 40, "the fetch resolved a commit")
   local fetched = tempDirectory()
   assert(template.write(assert(template.plan(source, fetched, {name = "sample"}))))

   local _, diff = shell("diff -r '" .. fromDisk .. "' '" .. fetched .. "'")
   assertEq(diff, "", "a fetched tree scaffolds exactly as the directory does")
   remove(dir) remove(scratch) remove(fromDisk) remove(fetched)
end

function M.aRemoteTemplateCanLiveInASubdirectory()
   local dir, url = repository({
      ["templates/game/template.lua"] = "return {}",
      ["templates/game/main.nupp"] = 'print("${name}")',
      ["README.md"] = "the repository, not the template",
   })
   local scratch = tempDirectory()
   os.execute("mkdir -p '" .. scratch .. "'")
   local source = {kind = "remote", url = url, subdir = "templates/game"}
   assert(template.fetch(source, scratch))
   local into = tempDirectory()
   local plan = assert(template.plan(source, into, {name = "mygame"}))
   assertEq(#plan.files, 1, "only the subdirectory was taken")
   assertEq(plan.files[1].output, "main.nupp", "and it is the template's own file")
   remove(dir) remove(scratch) remove(into)
end

function M.aTreeThatIsNotATemplateIsRefusedAfterFetching()
   local dir, url = repository({["README.md"] = "not a template"})
   local scratch = tempDirectory()
   os.execute("mkdir -p '" .. scratch .. "'")
   local fetched, err = template.fetch({kind = "remote", url = url}, scratch)
   assertEq(fetched, nil, "a repository without a manifest is not a template")
   assert(err:find("template.lua", 1, true), err)
   remove(dir) remove(scratch)
end

-- The step restriction ------------------------------------------------------

function M.aRemoteTemplateNeverCausesItsOwnManifestToBeLoaded()
   -- The executable form of the boundary. The scaffolded `nupp.lua` writes a
   -- sentinel when it is loaded, and `check` is what loads it. A local template
   -- gets that step and a fetched one does not, so the sentinel is the evidence
   -- that a fetched tree ran nothing.
   local sentinel = tempDirectory()
   local files = {
      ["template.lua"] = [[return {after = {"check"}}]],
      ["nupp.lua"] = ([[
         local f = io.open(%q, "w")
         if f then f:write("loaded") f:close() end
         return {include = {"src"}}
      ]]):format(sentinel),
      ["src/mod.nupp"] = "return {}",
   }
   local dir, url = repository(files)

   local localPlan = assert(template.plan({kind = "directory", path = dir},
      tempDirectory()))
   assertEq(#localPlan.steps, 1, "a local template keeps its step")
   assertEq(localPlan.steps[1], "check", "and it is check")
   assertEq(#localPlan.dropped, 0, "with nothing dropped")

   local scratch = tempDirectory()
   os.execute("mkdir -p '" .. scratch .. "'")
   local source = assert(template.resolve(url))
   assert(template.fetch(source, scratch))
   local remotePlan = assert(template.plan(source, tempDirectory()))
   assertEq(#remotePlan.steps, 0, "a fetched template keeps no step that loads it")
   assertEq(remotePlan.dropped[1], "check", "and says which one it lost")

   -- And the step itself, run for real, is what would have written the sentinel.
   local into = tempDirectory()
   assert(template.write(assert(template.plan({kind = "directory", path = dir}, into))))
   assert(not exists(sentinel), "nothing has loaded the manifest yet")
   template.step("check", into, NUPP)
   assert(exists(sentinel),
      "the check step loads the scaffolded manifest, which is why a remote may not ask for it")

   remove(dir) remove(scratch) remove(into) os.remove(sentinel)
end

function M.gitIsTheOneStepARemoteKeeps()
   local dir, url = repository({
      ["template.lua"] = [[return {after = {"git", "check", "build", "test"}}]],
      ["a.txt"] = "x",
   })
   local scratch = tempDirectory()
   os.execute("mkdir -p '" .. scratch .. "'")
   local source = assert(template.resolve(url))
   assert(template.fetch(source, scratch))
   local plan = assert(template.plan(source, tempDirectory()))
   assertEq(#plan.steps, 1, "one step survives")
   assertEq(plan.steps[1], "git", "and it is the one that runs no supplied code")
   assertEq(#plan.dropped, 3, "the other three are dropped")
   remove(dir) remove(scratch)
end

-- Acceptance: the scaffolded projects actually work -------------------------

local function scaffoldAndVerify(name, project, expectedOutput, prepare)
   local into = tempDirectory()
   local plan = assert(template.plan(assert(template.resolve(name)), into,
      {name = project}))
   assert(template.write(plan))
   if prepare then prepare(into) end

   local quoted = "cd '" .. into .. "' && NUPP=" .. NUPP .. " "
   local ok, out = shell(quoted .. NUPP .. " check")
   assert(ok, name .. " does not check:\n" .. out)
   ok, out = shell(quoted .. NUPP .. " build")
   assert(ok, name .. " does not build:\n" .. out)
   ok, out = shell(quoted .. NUPP .. " test")
   assert(ok, name .. " does not pass its own tests:\n" .. out)
   if expectedOutput then
      ok, out = shell(quoted .. NUPP .. " run src/main.nupp")
      assert(ok, name .. " does not run:\n" .. out)
      assert(out:find(expectedOutput, 1, true),
         name .. " ran but printed " .. out .. " rather than " .. expectedOutput)
   end
   remove(into)
end

function M.theAppTemplateChecksBuildsTestsAndRuns()
   scaffoldAndVerify("app", "greeter", "Hello, world!")
end

function M.theLibTemplateChecksBuildsAndTests()
   -- No `run`: a library has no entry point, and its test is what exercises it.
   scaffoldAndVerify("lib", "sample-lib", nil)
end

function M.theLoveTemplateChecksBuildsAndTests()
   -- LÖVE owns the event loop, so its host integration is not part of this
   -- headless suite. The template's game logic and generated module tree are.
   local definitions, url = repository({["library/love.lua"] = [[
---@class love
---@field graphics love.graphics
---@field load fun()
---@field update fun(elapsed: number)
---@field draw fun()
---@type love
---@class love.graphics
---@field setBackgroundColor fun(red: number, green: number, blue: number)
---@field setColor fun(red: number, green: number, blue: number)
---@field rectangle fun(mode: string, x: number, y: number, width: number, height: number)
love = {graphics = {}}
]]})
   local ok, revision = shell("cd '" .. definitions .. "' && git rev-parse HEAD")
   assert(ok, revision)
   revision = assert(revision:match("[0-9a-f]+"))
   scaffoldAndVerify("love", "sample-love", nil, function(into)
      local path = into .. "/nupp.lua"
      local file = assert(io.open(path, "rb"))
      local text = file:read("*a")
      file:close()
      local function replace(before, after)
         local at = assert(text:find(before, 1, true), before .. " is present")
         text = text:sub(1, at - 1) .. after .. text:sub(at + #before)
      end
      replace("https://github.com/LuaCATS/love2d.git", url)
      replace("c630dd883cda128a19d850bd5e3911110b271609", revision)
      file = assert(io.open(path, "wb"))
      file:write(text)
      file:close()
   end)
   remove(definitions)
end

-- A game template's manifest ------------------------------------------------

function M.aGameShapedManifestNeedsNoFieldsTheBuildDoesNotHave()
   -- The claim the whole Tecs case rests on: a template that wants a graphics
   -- host, a native dependency, assets and a run task asks for it in fields
   -- `nupp.lua` already validates. The Tecs template itself belongs in the Tecs
   -- repository; what belongs here is the evidence that it will not need a
   -- build change, checked by the validator rather than by reading.
   --
   -- The Cargo shape is the part worth pinning down, because the obvious
   -- spelling is wrong. `source = {git = ..., rev = ...}` is a `c` dependency
   -- key; a Cargo dependency names a local crate with `manifest`, and that
   -- crate's own Cargo.toml is what pins the engine.
   local manifest = require("nupp.compiler.build.manifest")
   local dir = templateDirectory({
      ["template.lua"] = [[return {description = "a game", raw = {"assets/**"}}]],
      ["nupp.lua"] = [[
         return {
            include = {"src"},
            dependencies = {
               host = {kind = "cargo", manifest = "host/Cargo.toml", library = "tecs_host"},
            },
            build = {
               outDir = "build",
               default = "game",
               targets = {
                  game = {
                     kind = "binary",
                     entries = {"main"},
                     dependencies = {"host"},
                     stub = "tecs",
                     resources = {"assets/**"},
                     output = "build/${name}",
                  },
               },
            },
            tasks = {play = {description = "Run it", argv = {"nupp", "run", "src/main.nupp"}}},
         }
      ]],
      ["src/main.nupp"] = "return {}",
      ["host/Cargo.toml"] = '[package]\nname = "tecs_host"\n',
      ["assets/sprite.bin"] = "\0\1\2\3",
   })
   local into = tempDirectory()
   local plan = assert(template.plan({kind = "directory", path = dir}, into,
      {name = "mygame"}))

   local assets
   for _, file in ipairs(plan.files) do
      if file.output == "assets/sprite.bin" then assets = file end
   end
   assert(assets, "the asset was carried")
   assert(assets.verbatim, "a raw glob keeps a binary file out of substitution")
   assertEq(assets.text, "\0\1\2\3", "byte for byte")

   assert(template.write(plan))
   local config, err = manifest.load(into)
   assert(config, "the scaffolded manifest does not validate: " .. tostring(err))
   assertEq(config.dependencies.host.kind, "cargo", "the cargo dependency stands")
   assertEq(config.build.targets.game.stub, "tecs", "and so does a non-default stub")
   assertEq(config.build.targets.game.output, "build/mygame",
      "with the project name substituted into it")
   remove(dir) remove(into)
end

return M
