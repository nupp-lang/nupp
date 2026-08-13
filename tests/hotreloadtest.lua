local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.env")
local gen = require("nupp.compiler.gen")
local hot = require("nupp.hotreload")
local hotSession = require("nupp.compiler.hot_session")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s: want %s, got %s"):format(label, tostring(want), tostring(got)), 2)
   end
end

local function checked(source, filename)
   filename = filename or "hot.g.nupp"
   local result = parser.parse(source, filename)
   assertEq(#result.errors, 0, "hot source parses")
   local diagnostics = check.check(result, filename, envMod.new("."))
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.code:match("^NUPP[123]") then
         error(("hot source did not check: %s: %s"):format(diagnostic.code, diagnostic.msg), 2)
      end
   end
   return result
end

local function generate(source, mode, module)
   local result = checked(source)
   local code, diagnostics, _, _, metadata = gen.generate(result, "hot.g.nupp", nil, {
      mode = mode,
      module = module or "hot",
      baseGeneration = mode == "patch" and hot.generation() or nil,
   })
   assertEq(#diagnostics, 0, mode .. " generation diagnostics")
   assert(metadata and metadata.mode == mode, mode .. " metadata")
   local chunk, reason = loadstring(code, "@hot-generated")
   assert(chunk, tostring(reason) .. "\n---\n" .. code)
   return code, chunk, metadata
end

local function initial(source, module)
   hot.resetForTesting()
   local _, chunk, metadata = generate(source, "initial", module)
   local value = chunk()
   hot.seal(metadata.module)
   return value, metadata
end

local M = {}

local function temporaryProject(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'"))
   for name, source in pairs(files) do
      local handle = assert(io.open(dir .. "/" .. name, "wb"))
      handle:write(source)
      handle:close()
   end
   return dir
end

local function write(path, source)
   local handle = assert(io.open(path, "wb"))
   handle:write(source)
   handle:close()
end

local function loadedCompilerSession(dir, path)
   local session = hotSession.new(dir, {cache = false})
   local initialBuild = session:initial({path})
   if initialBuild.kind ~= "initial" then
      local messages = {}
      for _, diagnostic in ipairs(initialBuild.diagnostics or {}) do
         messages[#messages + 1] = diagnostic.code .. ": " .. diagnostic.msg
      end
      error("initial hot build failed: " .. table.concat(messages, "; "), 2)
   end
   session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)
   return session
end

function M.normalGenerationRemainsByteIdentical()
   local result = checked("local function f(n: integer): integer return n + 1 end\nreturn f")
   local ordinary = assert(gen.generate(result, "ordinary.g.nupp"))
   local explicit = assert(gen.generate(result, "ordinary.g.nupp", nil, nil))
   assertEq(explicit, ordinary, "absent watch request changes normal output")
   assert(not ordinary:find("__nuppHot", 1, true), "normal output contains hot runtime")
end

function M.retainedFunctionUsesPatchedBodyAndCapturedCell()
   local before = table.concat({
      "local value: integer = 1",
      "local function advance(by: integer): integer",
      "   value = value + by",
      "   return value",
      "end",
      "return {advance = advance}",
   }, "\n")
   local api = initial(before, "capture")
   local retained = api.advance
   assertEq(retained(1), 2, "initial implementation")

   local after = table.concat({
      "local value: integer = 999",
      "local function advance(by: integer): integer",
      "   value = value + by * 2",
      "   return value",
      "end",
      "return {advance = advance}",
   }, "\n")
   local patch = generate(after, "patch", "capture")
   local prepared, reason = hot.stage(patch, hot.generation())
   assert(prepared, reason)
   assertEq(hot.commit(prepared), 2, "committed generation")
   assertEq(api.advance, retained, "public function identity")
   assertEq(retained(1), 4, "patched implementation shares old value cell")
end

function M.commitFlushesJitAfterPublishing()
   local before = "local function value(): integer return 1 end\nreturn value"
   local retained = initial(before, "jit-flush")
   local patch = generate(before:gsub("return 1", "return 2"), "patch", "jit-flush")
   local prepared, reason = hot.stage(patch, hot.generation())
   assert(prepared, reason)
   local original = jit.flush
   local flushes = 0
   jit.flush = function()
      flushes = flushes + 1
   end
   local ok, generation, commitError = pcall(hot.commit, prepared)
   jit.flush = original
   assert(ok, generation)
   assertEq(generation, 2, commitError)
   assertEq(flushes, 1, "commit flushes stale JIT traces exactly once")
   assertEq(retained(), 2, "the flushed generation was published")
end

function M.rejectedCaptureChangeLeavesOldGenerationRunning()
   local before = table.concat({
      "local value: integer = 3",
      "local function read(): integer",
      "   return value",
      "end",
      "return read",
   }, "\n")
   local retained = initial(before, "reject")

   local after = table.concat({
      "local value: integer = 3",
      "local other: integer = 4",
      "local function read(): integer",
      "   return value + other",
      "end",
      "return read",
   }, "\n")
   local patch = generate(after, "patch", "reject")
   local prepared, reason = hot.stage(patch, hot.generation())
   assertEq(prepared, nil, "capture-changing patch is rejected")
   assert(reason and reason:find("captured bindings changed", 1, true), tostring(reason))
   assertEq(hot.generation(), 1, "rejection does not publish generation")
   assertEq(retained(), 3, "old implementation remains callable")
end

function M.selfRecursionUsesNewPrivateImplementation()
   local before = table.concat({
      "local function sum(n: integer): number",
      "   if n == 0 then return 0 end",
      "   return n + sum(n - 1)",
      "end",
      "return sum",
   }, "\n")
   local retained = initial(before, "recursive")
   assertEq(retained(3), 6, "initial recursion")

   local after = table.concat({
      "local function sum(n: integer): number",
      "   if n == 0 then return 1 end",
      "   return n + sum(n - 1)",
      "end",
      "return sum",
   }, "\n")
   local patch = generate(after, "patch", "recursive")
   local prepared, reason = hot.stage(patch, hot.generation())
   assert(prepared, reason)
   assert(hot.commit(prepared))
   assertEq(retained(3), 7, "replacement self recursion stays on replacement")
end

function M.mutualRecursionUsesTheNewestPartnerSlot()
   local before = table.concat({
      "local M = {}",
      "function M.odd(n: integer): boolean",
      "   if n == 0 then return false end",
      "   return M.even(n - 1)",
      "end",
      "function M.even(n: integer): boolean",
      "   if n == 0 then return true end",
      "   return M.odd(n - 1)",
      "end",
      "return M",
   }, "\n")
   local api = initial(before, "mutual")
   local after = before:gsub("if n == 0 then return false end", "if n == 0 then return true end")
   local patch = generate(after, "patch", "mutual")
   local prepared, reason = hot.stage(patch, hot.generation())
   assert(prepared, reason)
   assert(hot.commit(prepared))
   assertEq(api.even(1), true, "unchanged partner dispatches through patched odd slot")
end

function M.inlineRecordMethodKeepsItsPublicIdentity()
   local before = table.concat({
      "local record Counter",
      "   value: integer",
      "   function add(self, by: integer): integer",
      "      return self.value + by",
      "   end",
      "end",
      "return Counter",
   }, "\n")
   local Counter = initial(before, "inline")
   local retained = Counter.add
   local instance = setmetatable({value = 3}, Counter)
   assertEq(retained(instance, 2), 5)
   local after = before:gsub("self.value %+ by", "self.value + by * 2")
   local patch = generate(after, "patch", "inline")
   local prepared, reason = hot.stage(patch, hot.generation())
   assert(prepared, reason)
   assert(hot.commit(prepared))
   assertEq(Counter.add, retained, "record method identity")
   assertEq(retained(instance, 2), 7, "record method replacement")
end

function M.structMethodDispatchesThroughAStableSlot()
   local before = table.concat({
      "local struct Counter",
      "   value: int32",
      "end",
      "function Counter:add(by: integer): number",
      "   return self.value + by",
      "end",
      "local item = new Counter(3)",
      "local function call(): number return item:add(2) end",
      "return call",
   }, "\n")
   local call = initial(before, "struct-method")
   assertEq(call(), 5)
   local after = before:gsub("self.value %+ by", "self.value + by * 2")
   local patch = generate(after, "patch", "struct-method")
   local prepared, reason = hot.stage(patch, hot.generation())
   assert(prepared, reason)
   assert(hot.commit(prepared))
   assertEq(call(), 7, "struct metatype method replacement")
end

function M.activeCallFinishesOnTheImplementationItEntered()
   local before = table.concat({
      "local function value(commit: function(): nil): integer",
      "   commit()",
      "   return 1",
      "end",
      "return value",
   }, "\n")
   local retained = initial(before, "active")
   local after = before:gsub("return 1", "return 2")
   local patch = generate(after, "patch", "active")
   local didCommit = false
   local oldResult = retained(function()
      local prepared, reason = hot.stage(patch, hot.generation())
      assert(prepared, reason)
      assert(hot.commit(prepared))
      didCommit = true
   end)
   assert(didCommit)
   assertEq(oldResult, 1, "active closure remains old")
   assertEq(retained(function() end), 2, "future dispatch enters replacement")
end

function M.failedMultiFunctionStagePublishesNothing()
   local before = table.concat({
      "local function first(): integer return 1 end",
      "local function second(): integer return 2 end",
      "return {first = first, second = second}",
   }, "\n")
   local api = initial(before, "atomic")
   local after = table.concat({
      "local captured: integer = 4",
      "local function first(): integer return 10 end",
      "local function second(): integer return 2 + captured end",
      "return {first = first, second = second}",
   }, "\n")
   local patch = generate(after, "patch", "atomic")
   local prepared, reason = hot.stage(patch, hot.generation())
   assertEq(prepared, nil)
   assert(reason and reason:find("captured bindings changed", 1, true), tostring(reason))
   assertEq(api.first(), 1, "earlier valid candidate was not published")
   assertEq(api.second(), 2, "failing candidate was not published")
end

function M.tailTrampolinePreservesErrorAttribution()
   local source = table.concat({
      "local function fail(): nil",
      "   error('boom', 2)",
      "end",
      "local function call(): nil fail() end",
      "return call",
   }, "\n")
   local result = checked(source, "stack.g.nupp")
   local ordinary = assert(gen.generate(result, "stack.g.nupp"))
   local normalChunk = assert(loadstring(ordinary, "@stack.g.nupp"))
   local normal = normalChunk()
   local normalOK, normalReason = pcall(normal)
   assertEq(normalOK, false)

   hot.resetForTesting()
   local watchCode, diagnostics, _, _, metadata = gen.generate(result, "stack.g.nupp", nil, {
      mode = "initial",
      module = "stack",
   })
   assertEq(#diagnostics, 0)
   local watch = assert(loadstring(watchCode, "@stack.g.nupp"))()
   hot.seal(metadata.module)
   local watchOK, watchReason = pcall(watch)
   assertEq(watchOK, false)
   assertEq(tostring(watchReason), tostring(normalReason), "error(level) source attribution")
end

function M.slotArrayMatchesTheNormalLocalBoundary()
   local function source(count)
      local lines = {}
      for index = 1, count do
         lines[#lines + 1] = ("local function f%d() return %d end"):format(index, index)
      end
      lines[#lines + 1] = ("return f%d"):format(count)
      return table.concat(lines, "\n")
   end
   local boundary
   for count = 180, 200 do
      local parsed = parser.parse(source(count), "locals.g.nupp")
      local code, diagnostics = gen.generate(parsed, "locals.g.nupp")
      if #diagnostics == 0 and loadstring(code, "@normal-locals") then
         boundary = count
      else
         break
      end
   end
   assert(boundary, "normal generator has no accepted boundary fixture")
   for _, count in ipairs({boundary, boundary + 1}) do
      local parsed = parser.parse(source(count), "locals.g.nupp")
      local normal, normalDiagnostics = gen.generate(parsed, "locals.g.nupp")
      local watch, watchDiagnostics = gen.generate(parsed, "locals.g.nupp", nil, {
         mode = "initial",
         module = "locals",
      })
      local normalLoads = #normalDiagnostics == 0 and loadstring(normal, "@normal-locals") ~= nil
      local watchLoads = #watchDiagnostics == 0 and loadstring(watch, "@watch-locals") ~= nil
      assertEq(watchLoads, normalLoads, "watch and normal local ceiling at " .. count)
   end
end

function M.sessionAdvancesOnlyAfterCommitAcknowledgement()
   local before = table.concat({
      "local value: integer = 1",
      "local function changed(by: integer): integer",
      "   value = value + by",
      "   return value",
      "end",
      "local function untouched(): integer return 9 end",
      "return {changed = changed, untouched = untouched}",
   }, "\n")
   local dir = temporaryProject({["main.nupp"] = before})
   local path = dir .. "/main.nupp"
   hot.resetForTesting()
   local session = hotSession.new(dir, {cache = false})
   local initialBuild = session:initial({path})
   assertEq(initialBuild.kind, "initial")
   local entry = assert(loadstring(initialBuild.entryCode, "@" .. path))
   local api = entry()
   hot.seal(initialBuild.entryManifest.module)
   session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)

   local after = before:gsub("value = value %+ by", "value = value + by * 2")
   write(path, after)
   session:diskChanged(path, 2)
   local prepared = session:prepare({path})
   assertEq(prepared.kind, "prepared")
   assert(prepared.patch:find("changed", 1, true), "changed implementation is emitted")
   assert(not prepared.patch:find("untouched", 1, true), "unchanged implementation is omitted")
   assertEq(session.generation, 1, "prepare does not advance compiler baseline")
   local staged, reason = hot.stage(prepared.patch, prepared.baseGeneration)
   assert(staged, reason)
   assertEq(hot.commit(staged), 2)
   session:committed(2)
   assertEq(api.changed(1), 3, "session patch reached retained function")
end

function M.sessionSkipsUnloadedChangedModules()
   local dir = temporaryProject({
      ["main.nupp"] = "local function main(): integer return 1 end\nreturn main",
      ["later.nupp"] = "local function later(): integer return 1 end\nreturn later",
   })
   local mainPath = dir .. "/main.nupp"
   local laterPath = dir .. "/later.nupp"
   hot.resetForTesting()
   local session = hotSession.new(dir, {cache = false})
   local initialBuild = session:initial({mainPath})
   assert(loadstring(initialBuild.entryCode, "@" .. mainPath))()
   hot.seal(initialBuild.entryManifest.module)
   session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)
   write(laterPath, "local function later(): integer return 2 end\nreturn later")
   session:diskChanged(laterPath, 2)
   local result = session:prepare({laterPath})
   assertEq(result.kind, "no-change", "unloaded module has no running slots to patch")
end

function M.sessionReportsStructuralChangesAsRestartRequired()
   local before = "local function value(): integer return 1 end\nreturn value"
   local dir = temporaryProject({["main.nupp"] = before})
   local path = dir .. "/main.nupp"
   hot.resetForTesting()
   local session = hotSession.new(dir, {cache = false})
   local initialBuild = session:initial({path})
   assert(loadstring(initialBuild.entryCode, "@" .. path))()
   hot.seal(initialBuild.entryManifest.module)
   session:loaded(initialBuild.entryManifest.module, 1, initialBuild.entryManifest)
   write(path, "local added: integer = 2\n" .. before)
   session:diskChanged(path, 2)
   local result = session:prepare({path})
   assertEq(result.kind, "restart-required")
   assertEq(result.diagnostics[1].code, "NUPP5001")
   assertEq(result.reason.kind, "source-structure")
   assertEq(result.reason.dependency, "main")
   assertEq(result.reason.path, path)
end

function M.sessionRechecksLoadedModulesAfterDeclarationChanges()
   local dir = temporaryProject({
      ["globals.nupp"] = "global type Watched = number\n",
      ["main.nupp"] = table.concat({
         "local function add(value: Watched): number",
         "   return value + 1",
         "end",
         "return add",
      }, "\n"),
   })
   local mainPath = dir .. "/main.nupp"
   local globalsPath = dir .. "/globals.nupp"
   local session = loadedCompilerSession(dir, mainPath)

   write(globalsPath, "global type Watched = string\n")
   session:diskChanged(globalsPath, 2)
   local result = session:prepare({globalsPath})
   assertEq(result.kind, "diagnostics", "dependent is type-checked before patching")
   assert(result.diagnostics[1].code:match("^NUPP[123]"), "expected a fatal type diagnostic")
end

function M.sessionRejectsSemanticSignatureChangesWithTheSameSpelling()
   local dir = temporaryProject({
      ["globals.nupp"] = "global type Watched = int32\n",
      ["main.nupp"] = table.concat({
         "local function identity(value: Watched): Watched",
         "   return value",
         "end",
         "return identity",
      }, "\n"),
   })
   local mainPath = dir .. "/main.nupp"
   local globalsPath = dir .. "/globals.nupp"
   local session = loadedCompilerSession(dir, mainPath)

   write(globalsPath, "global type Watched = int64\n")
   session:diskChanged(globalsPath, 2)
   local result = session:prepare({globalsPath})
   assertEq(result.kind, "restart-required")
   assertEq(result.diagnostics[1].code, "NUPP5001")
   assertEq(result.reason.kind, "project-declaration")
   assertEq(result.reason.dependency, "Watched")
   assertEq(result.reason.path, globalsPath)
   assertEq(result.reason.consumer, "main")
   assert(result.diagnostics[1].msg:find(globalsPath, 1, true), result.diagnostics[1].msg)
   assert(result.diagnostics[1].msg:find("required by main", 1, true), result.diagnostics[1].msg)
end

function M.sessionNamesTheImportedModuleWhoseInterfaceChanged()
   local dir = temporaryProject({
      ["dependency.nupp"] = table.concat({
         "local M = {}",
         "function M.identity(value: int32): int32 return value end",
         "return M",
      }, "\n"),
      ["main.nupp"] = "local dependency = require('dependency')\nreturn dependency.identity\n",
   })
   local mainPath = dir .. "/main.nupp"
   local dependencyPath = dir .. "/dependency.nupp"
   local session = loadedCompilerSession(dir, mainPath)

   write(dependencyPath, table.concat({
      "local M = {}",
      "function M.identity(value: int64): int64 return value end",
      "return M",
   }, "\n"))
   session:diskChanged(dependencyPath, 2)
   local result = session:prepare({dependencyPath})
   assertEq(result.kind, "restart-required")
   assertEq(result.reason.kind, "module-interface")
   assertEq(result.reason.dependency, "dependency")
   assertEq(result.reason.path, dependencyPath)
   assertEq(result.reason.consumer, "main")
   assert(result.diagnostics[1].msg:find("module interface dependency", 1, true),
      result.diagnostics[1].msg)
   assert(result.diagnostics[1].msg:find(dependencyPath, 1, true), result.diagnostics[1].msg)
end

function M.sessionRejectsChangedCLayoutsBeforePatching()
   local dir = temporaryProject({
      ["native.nupp"] = table.concat({
         "cdef struct hot_point",
         "   value: int32",
         "end",
         "return {hot_point = hot_point}",
      }, "\n"),
      ["main.nupp"] = table.concat({
         "local native = require('native')",
         "return native.hot_point",
      }, "\n"),
   })
   local mainPath = dir .. "/main.nupp"
   local nativePath = dir .. "/native.nupp"
   local session = loadedCompilerSession(dir, mainPath)

   write(nativePath, table.concat({
      "cdef struct hot_point",
      "   value: int64",
      "end",
      "return {hot_point = hot_point}",
   }, "\n"))
   session:diskChanged(nativePath, 2)
   local result = session:prepare({nativePath})
   assertEq(result.kind, "restart-required")
   assertEq(result.diagnostics[1].code, "NUPP5001")
   assertEq(result.reason.kind, "c-declaration")
   assertEq(result.reason.dependency, "native")
   assertEq(result.reason.path, nativePath)
   assertEq(result.reason.consumer, "main")
   assert(result.diagnostics[1].msg:find("C declarations in module native", 1, true),
      result.diagnostics[1].msg)
   assert(result.diagnostics[1].msg:find(nativePath, 1, true), result.diagnostics[1].msg)
end

function M.sessionNamesTheAffineCaptureThatRequiresRestart()
   local before = table.concat({
      "local record Resource",
      "   value: integer",
      "end",
      "local function closeResource(resource: Resource): nil end",
      "@owned(closeResource)",
      "local function openResource(): Resource",
      "   return new Resource(value = 7)",
      "end",
      "local resource = openResource()",
      "local function read(): integer takes (resource)",
      "   return resource.value",
      "end",
      "return read()",
   }, "\n")
   local dir = temporaryProject({["main.nupp"] = before})
   local path = dir .. "/main.nupp"
   local session = loadedCompilerSession(dir, path)

   write(path, before:gsub("return resource.value", "return resource.value + 1"))
   session:diskChanged(path, 2)
   local result = session:prepare({path})
   assertEq(result.kind, "restart-required")
   assertEq(result.reason.kind, "affine-capture")
   assertEq(result.reason.capture, "resource")
   assert(result.diagnostics[1].msg:find("capture resource", 1, true), result.diagnostics[1].msg)
   assert(result.diagnostics[1].msg:find("main/module/local/read", 1, true), result.diagnostics[1].msg)
end

function M.sessionIgnoresUnrelatedDeclarationChanges()
   local dir = temporaryProject({
      ["globals.nupp"] = table.concat({
         "global type Watched = number",
         "global type Unused = number",
      }, "\n"),
      ["main.nupp"] = "local value: Watched = 1\nreturn value\n",
   })
   local mainPath = dir .. "/main.nupp"
   local globalsPath = dir .. "/globals.nupp"
   local session = loadedCompilerSession(dir, mainPath)

   write(globalsPath, table.concat({
      "global type Watched = number",
      "global type Unused = string",
   }, "\n"))
   session:diskChanged(globalsPath, 2)
   local result = session:prepare({globalsPath})
   assertEq(result.kind, "no-change", "unobserved declarations stop at the query boundary")
end

return M
