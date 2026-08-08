local query = require("nupp.query")
local incremental = require("nupp.incremental")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local M = {}

function M.memoizationAndInvalidation()
   local q = query.new()
   q:setInput("src", "a", 10)
   q:define("double", function(self, key)
      return self:get("src", key) * 2
   end)
   assertEq(q:get("double", "a"), 20)
   assertEq(q:get("double", "a"), 20)
   assertEq(q.stats.double, 1, "memoized within revision")
   q:setInput("src", "a", 21)
   assertEq(q:get("double", "a"), 42)
   assertEq(q.stats.double, 2, "recomputed after input change")
end

function M.earlyCutoff()
   local q = query.new()
   q:setInput("src", "a", 10)
   -- parity only changes when crossing even/odd — downstream must not
   -- recompute when parity is stable
   q:define("parity", function(self, key)
      return self:get("src", key) % 2
   end)
   q:define("report", function(self, key)
      return "parity is " .. self:get("parity", key)
   end)
   assertEq(q:get("report", "a"), "parity is 0")
   q:setInput("src", "a", 12) -- still even
   assertEq(q:get("report", "a"), "parity is 0")
   assertEq(q.stats.parity, 2, "parity recomputed")
   assertEq(q.stats.report, 1, "report NOT recomputed (cutoff)")
   q:setInput("src", "a", 13) -- odd: real change propagates
   assertEq(q:get("report", "a"), "parity is 1")
   assertEq(q.stats.report, 2)
end

-- The compiler-level behavior: editing a dependency's BODY must not
-- recheck the dependent; editing its INTERFACE must.
function M.interfaceCutoffAcrossModules()
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local depPath = dir .. "/dep.nupp"
   local mainPath = dir .. "/main.nupp"

   local function write(path, text)
      local f = assert(io.open(path, "wb"))
      f:write(text)
      f:close()
   end

   local depV1 = table.concat({
      "local function scale(n: number): number",
      "   return n * 2",
      "end",
      "return { scale = scale }",
   }, "\n")
   write(depPath, depV1)
   write(mainPath, table.concat({
      "local dep = require('dep')",
      "local x: number = dep.scale(21)",
   }, "\n"))

   local inc = incremental.new(dir)
   local r = inc.checkFile(mainPath)
   assertEq(#r.diags, 0, "cold check clean")
   local coldChecks = inc.q.stats.checkModule
   assertEq(coldChecks, 2, "main + dep checked cold")

   -- body edit: same interface
   inc.changeDocument(depPath, (depV1:gsub("n %* 2", "n * 3")))
   local r2 = inc.checkFile(mainPath)
   assertEq(#r2.diags, 0)
   assertEq(inc.q.stats.checkModule, coldChecks + 1,
      "only dep rechecked after a body edit (interface cutoff)")

   -- interface edit: return type changes, dependent must recheck and fail
   inc.changeDocument(depPath, (depV1:gsub("%): number", "): string")
      :gsub("n %* 2", "tostring(n)")))
   local r3 = inc.checkFile(mainPath)
   assertEq(inc.q.stats.checkModule, coldChecks + 3,
      "dep AND main rechecked after an interface edit")
   assertEq(r3.diags[1] and r3.diags[1].code, "NUPP2001",
      "dependent sees the new interface")

   os.execute("rm -rf '" .. dir .. "'")
end

function M.overlayClearRevertsToDisk()
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local path = dir .. "/m.nupp"
   local f = assert(io.open(path, "wb"))
   f:write("return { ok = 1 }")
   f:close()

   local inc = incremental.new(dir)
   assertEq(#inc.checkFile(path).diags, 0)
   inc.changeDocument(path, "local x: number = 'broken'")
   assertEq(inc.checkFile(path).diags[1].code, "NUPP2001", "overlay wins")
   inc.closeDocument(path)
   assertEq(#inc.checkFile(path).diags, 0, "disk content restored")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.diskWatcherChangesInvalidateQueriesAndProjectFiles()
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local mainPath = dir .. "/main.nupp"
   local globalsPath = dir .. "/globals.nupp"
   local function write(path, text)
      local f = assert(io.open(path, "wb"))
      f:write(text)
      f:close()
   end
   write(mainPath, "local value: Watched = 1\n")

   local inc = incremental.new(dir)
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2101",
      "missing watched declaration starts as an error")
   write(globalsPath, "global type Watched = number\n")
   inc.diskChanged(globalsPath, 1)
   assertEq(#inc.checkFile(mainPath).diags, 0,
      "created disk file joins the project index")

   write(globalsPath, "global type Watched = string\n")
   inc.diskChanged(globalsPath, 2)
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2001",
      "changed disk file invalidates dependent checks")

   os.remove(globalsPath)
   inc.diskChanged(globalsPath, 3)
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2101",
      "deleted disk file leaves the project index")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.diskWatcherPreservesOpenOverlay()
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local path = dir .. "/main.nupp"
   local function write(text)
      local f = assert(io.open(path, "wb"))
      f:write(text)
      f:close()
   end
   write("local value: number = 1\n")
   local inc = incremental.new(dir)
   inc.openDocument(path, "local value: number = 2\n")
   write("local value: number = 'disk error'\n")
   inc.diskChanged(path, 2)
   assertEq(#inc.checkFile(path).diags, 0,
      "disk event does not replace an editor overlay")
   inc.closeDocument(path)
   assertEq(inc.checkFile(path).diags[1].code, "NUPP2001",
      "closing the overlay observes the changed disk file")
   os.execute("rm -rf '" .. dir .. "'")
end

function M.projectIndexTracksOverlaysAndDependents()
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local modelPath = dir .. "/model.nupp"
   local mainPath = dir .. "/main.nupp"
   local modelFile = assert(io.open(modelPath, "wb"))
   modelFile:write("local record Shared\n   value: number\nend\n")
   modelFile:close()
   local mainFile = assert(io.open(mainPath, "wb"))
   mainFile:write(table.concat({
      "local item: Shared = new Shared {}",
      "local value: number = item.value",
   }, "\n"))
   mainFile:close()

   local inc = incremental.new(dir)
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2101",
      "disk-private declaration is hidden")
   inc.openDocument(modelPath,
      "global record Shared\n   value: number\nend\n")
   assertEq(#inc.checkFile(mainPath).diags, 0,
      "unsaved export enters the project index")
   inc.changeDocument(modelPath,
      "global record Shared\n   value: string\nend\n")
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2001",
      "export change rechecks its dependent")
   inc.closeDocument(modelPath)
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2101",
      "closing the overlay restores disk visibility")

   os.execute("rm -rf '" .. dir .. "'")
end

function M.newOverlayFilesJoinProjectIndex()
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local mainPath = dir .. "/main.nupp"
   local mainFile = assert(io.open(mainPath, "wb"))
   mainFile:write("local value: Added\n")
   mainFile:close()

   local inc = incremental.new(dir)
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2101")
   local addedPath = dir .. "/added.nupp"
   inc.openDocument(addedPath, "global type Added = number\n")
   assertEq(#inc.checkFile(mainPath).diags, 0,
      "new unsaved file joins project index")
   inc.closeDocument(addedPath)
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2101",
      "closing new unsaved file removes it from project index")

   os.execute("rm -rf '" .. dir .. "'")
end

function M.removingGlobalOverlayInvalidatesDependents()
   local dir = os.tmpname()
   os.remove(dir)
   os.execute("mkdir -p '" .. dir .. "'")
   local globalsPath = dir .. "/globals.nupp"
   local mainPath = dir .. "/main.nupp"
   local globalsFile = assert(io.open(globalsPath, "wb"))
   globalsFile:write("global type SharedId = number\n")
   globalsFile:close()
   local mainFile = assert(io.open(mainPath, "wb"))
   mainFile:write("local value: SharedId = 1\n")
   mainFile:close()

   local inc = incremental.new(dir)
   assertEq(#inc.checkFile(mainPath).diags, 0, "global export is visible")
   inc.changeDocument(globalsPath, "local type SharedId = number\n")
   assertEq(inc.checkFile(mainPath).diags[1].code, "NUPP2101",
      "removed global export does not survive in ambient state")

   os.execute("rm -rf '" .. dir .. "'")
end

-- A bundled module is loaded when something asks for it. Together they cost
-- about as much as the prelude, and a file that does not require `ffi` is not
-- made any more correct by the compiler having worked out what `ffi` would
-- have meant. Both halves matter and only one of them is obvious: the loading
-- has to be lazy, and it also has to happen at most once either way, because
-- the miss is what an ordinary unresolved name hits on every lookup.
function M.bundledModulesAreLoadedWhenSomethingAsksForThem()
   local envMod = require("nupp.env")
   local check = require("nupp.check")
   local checked = {}
   local original = check.check
   check.check = function(result, filename, ...)
      checked[filename] = (checked[filename] or 0) + 1
      return original(result, filename, ...)
   end

   local dir = "/tmp/nupp-lazy-decls-" .. tostring(os.time())
   os.execute("mkdir -p '" .. dir .. "'")

   -- Whatever happens, the checker goes back. Counting what gets checked
   -- means replacing `check.check` for the length of this test, and a failure
   -- part way through used to leave the replacement installed for every test
   -- after it -- which does not read as this test's fault when the suite
   -- crashes four tests later.
   local ok, err = pcall(function()
      local env = envMod.new(dir, {cache = false})
      assertEq(checked["ffi"], nil, "building an environment does not check ffi")
      assertEq(checked["cjson"], nil, "nor cjson")
      assertEq(checked["nupp.std.zone"], nil, "nor the standard library")

      -- Asking is what loads it, and asking twice does not check it twice.
      assert(env.bundled["ffi"], "ffi is still there when wanted")
      assertEq(checked["ffi"], 1, "asking for ffi checks it")
      assert(env.bundled["ffi"], "and it is still there the second time")
      assertEq(checked["ffi"], 1, "asking again does not check it again")
      assertEq(checked["cjson"], nil, "and does not drag the others in")

      -- A name nothing bundles is remembered as absent rather than looked for
      -- again, which is what every unresolved name in a project would
      -- otherwise do on every lookup.
      assertEq(env.bundled["not.a.bundled.module"], false,
         "an unbundled name is absent, not a failure")
      assertEq(rawget(env.bundled, "not.a.bundled.module"), false,
         "and the absence is remembered")
   end)

   check.check = original
   os.execute("rm -rf '" .. dir .. "'")
   if not ok then error(err, 0) end
end

return M
