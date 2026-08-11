local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local fmt = require("nupp.compiler.fmt")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local cwdPipe = assert(io.popen("pwd"))
local currentDir = assert(cwdPipe:read("*l"))
cwdPipe:close()
local ROOT = HERE:sub(1, 1) == "/" and (HERE .. "/..")
   or (currentDir .. "/" .. HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s: want %s, got %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function readFile(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local function writeFile(path, text)
   local parent = assert(path:match("^(.*)[/\\]"))
   assert(os.execute("mkdir -p '" .. parent .. "'") == 0)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function withProject(files, callback)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for path, text in pairs(files) do writeFile(dir .. "/" .. path, text) end
   local ok, result = pcall(callback, dir)
   os.execute("rm -rf '" .. dir .. "'")
   if not ok then error(result, 0) end
   return result
end

local function checkFile(env, path)
   local parsed = parser.parse(readFile(path), path)
   if #parsed.errors > 0 then return parsed.errors end
   return check.check(parsed, path, env)
end

local function projectEnv(dir)
   local env = envMod.new(dir, {config = {include = {"src"}}})
   local files = envMod.listProjectFiles(env)
   assert(#files > 0,
      "project discovery found no files under " .. dir)
   return env
end

local M = {}

function M.ambiguousGlobalsCarryBothDeclarationLocations()
   withProject({
      ["src/a.g.nupp"] = "global record Shared end\n",
      ["src/b.g.nupp"] = "global record Shared end\n",
      ["src/use.g.nupp"] = "local value: Shared\n",
   }, function(dir)
      local diags = checkFile(projectEnv(dir), dir .. "/src/use.g.nupp")
      assertEq(diags[1] and diags[1].code, "NUPP2102")
      assertEq(#(diags[1].related or {}), 2,
         "both conflicting declarations are related")
      assert(diags[1].related[1].filename:match("[ab]%.g%.nupp$"),
         "related location names its file")
      assert(diags[1].help:find("module tables", 1, true),
         "diagnostic gives a repair direction")
   end)
end

-- A declaration has to say where it lives. Plain Lua would have made an
-- undecorated name a global, so the same spelling is refused rather than
-- quietly meaning something else here.
function M.rejectsADeclarationWithNoVisibility()
   withProject({
      ["src/model.g.nupp"] = "local model = {}\nrecord Loose\n    id: uint32\n"
         .. "end\nreturn model\n",
   }, function(dir)
      local diags = checkFile(projectEnv(dir), dir .. "/src/model.g.nupp")
      assertEq(diags[1] and diags[1].code, "NUPP2119",
         "a declaration naming no visibility is refused")
      assert(diags[1].msg:find("model.Loose", 1, true),
         "the message names the table it would attach to: " .. diags[1].msg)
   end)
end

-- Attaching to some other table is not an export: only the table the file
-- hands back is the module.
function M.aDeclarationOnAnotherTableStaysFilePrivate()
   withProject({
      ["src/model.g.nupp"] = [[
local model = {}
local internal = {}

record internal.Hidden
    id: uint32
end

return model
]],
      ["src/use.g.nupp"] = "local model = require(\"model\")\n"
         .. "local hidden: model.Hidden\n",
   }, function(dir)
      local env = projectEnv(dir)
      assertEq(#checkFile(env, dir .. "/src/model.g.nupp"), 0,
         "attaching to a file-local table is fine")
      local diags = checkFile(env, dir .. "/src/use.g.nupp")
      assertEq(diags[1] and diags[1].code, "NUPP2101",
         "a declaration on another table is not a module member")
   end)
end

-- The module is still the module when it is handed back wrapped.
function M.recognizesAModuleReturnedThroughSetmetatable()
   withProject({
      ["src/model.g.nupp"] = [[
local model = {}

record model.Wrapped
    id: uint32
end

return setmetatable(model, {})
]],
      ["src/use.g.nupp"] = "local model = require(\"model\")\n"
         .. "local w: model.Wrapped = new model.Wrapped(id = 1)\n",
   }, function(dir)
      assertEq(#checkFile(projectEnv(dir), dir .. "/src/use.g.nupp"), 0,
         "setmetatable(M, ...) still returns M")
   end)
end

function M.linksExportedTypesAndModulesAcrossProject()
   withProject({
      ["src/model.g.nupp"] = [[
local model = {}

type model.EntityId = uint32

record model.Entity
    id: model.EntityId
end

local type Secret = string

model.value = 42

return model
]],
      ["src/feature/use.g.nupp"] = [[
local model = require("model")

local id: model.EntityId = 7
local entity: model.Entity
local value: number = model.value
]],
   }, function(dir)
      local path = dir .. "/src/feature/use.g.nupp"
      assertEq(#checkFile(projectEnv(dir), path), 0,
         "project links through the module a declaration was attached to")
   end)
end

function M.keepsLocalTypesFilePrivate()
   withProject({
      ["src/model.g.nupp"] = "local type Secret = string\n",
      ["src/use.g.nupp"] = "local value: Secret\n",
   }, function(dir)
      local diags = checkFile(projectEnv(dir), dir .. "/src/use.g.nupp")
      assertEq(diags[1] and diags[1].code, "NUPP2101",
         "local type visibility")
   end)
end

-- Two modules may each attach an `Item`, because neither name is loose in the
-- project: reaching one means naming the module it was attached to.
function M.qualifiesProjectTypesByModule()
   withProject({
      ["src/a/shared.g.nupp"] = "local shared = {}\ntype shared.Item = string\n"
         .. "return shared\n",
      ["src/b/shared.g.nupp"] = "local shared = {}\ntype shared.Item = number\n"
         .. "return shared\n",
      ["src/main.g.nupp"] = [[
local left: a.shared.Item = "ok"
local right: b.shared.Item = 1
]],
      ["src/unqualified.g.nupp"] = "local value: Item\n",
   }, function(dir)
      local env = projectEnv(dir)
      assertEq(#checkFile(env, dir .. "/src/main.g.nupp"), 0,
         "qualified project types")
      local diags = checkFile(env, dir .. "/src/unqualified.g.nupp")
      assertEq(diags[1] and diags[1].code, "NUPP2101",
         "an unqualified project type is simply unknown")
   end)
end

-- A module is reached by requiring it. Its basename is not a name in scope, so
-- adding src/mathutil.g.nupp cannot give a bare `mathutil` a meaning somewhere
-- else in the project. Using one without requiring it is a program that does
-- not work, so a build refuses it rather than leaving it to run time; it is
-- still reported once per name.
function M.refusesAModuleUsedWithoutRequiringIt()
   withProject({
      ["src/mathutil.g.nupp"] = "local mathutil = {}\n"
         .. "function mathutil.double(v: number): number return v * 2 end\n"
         .. "return mathutil\n",
      ["src/use.g.nupp"] = "local a: number = mathutil.double(21)\n"
         .. "local b: number = mathutil.double(1)\n"
         .. "local c = neverHeardOf\n",
   }, function(dir)
      local diags = checkFile(projectEnv(dir), dir .. "/src/use.g.nupp")
      assertEq(#diags, 1, "reported once, not per use")
      assertEq(diags[1].code, "NUPP2120", "a missing require is reported")
      assertEq(diags[1].severity, "error",
         "a build refuses it rather than deferring the failure to run time")
      assert(diags[1].msg:find('require("mathutil")', 1, true),
         "the message names the require to write: " .. diags[1].msg)
   end)
end

-- Advice is for a name nothing has bound. Once the require is written there is
-- nothing to say, and a file is never told to require itself.
function M.givesNoRequireAdviceWhenThereIsNothingToFix()
   withProject({
      ["src/mathutil.g.nupp"] = "local mathutil = {}\n"
         .. "function mathutil.double(v: number): number return v * 2 end\n"
         .. "return mathutil\n",
      ["src/fixed.g.nupp"] = "local mathutil = require(\"mathutil\")\n"
         .. "local a: number = mathutil.double(21)\n",
      ["src/selfref.g.nupp"] = "local m = {}\nlocal x = selfref\nreturn m\n",
   }, function(dir)
      local env = projectEnv(dir)
      assertEq(#checkFile(env, dir .. "/src/fixed.g.nupp"), 0,
         "a written require leaves nothing to advise")
      assertEq(#checkFile(env, dir .. "/src/selfref.g.nupp"), 0,
         "a file is not told to require itself")
   end)
end

-- The advice replaces the vaguer report rather than joining it, and says
-- nothing about names no project file answers to.
function M.strictReportsUnknownNamesThatAreNotModules()
   withProject({
      ["src/mathutil.g.nupp"] = "local mathutil = {}\nreturn mathutil\n",
      ["src/use.g.nupp"] = "local a = mathutil.double(21)\n"
         .. "local b = mathutil.double(1)\n"
         .. "local c = neverHeardOf\n",
   }, function(dir)
      local path = dir .. "/src/use.g.nupp"
      local parsed = parser.parse(readFile(path), path)
      local diags = check.check(parsed, path, projectEnv(dir), {strict = true})
      local codes = {}
      for j, d in ipairs(diags) do codes[j] = d.code end
      assertEq(table.concat(codes, " "), "NUPP2120 NUPP2105",
         "one advice for the module, one unknown for the name nothing answers to")
   end)
end

function M.linksGlobalTypesWithoutImports()
   withProject({
      ["src/globals.g.nupp"] = "global type ProjectId = uint32\n",
      ["src/use.g.nupp"] = "local id: ProjectId = 9\n",
   }, function(dir)
      assertEq(#checkFile(projectEnv(dir), dir .. "/src/use.g.nupp"), 0,
         "global project type")
   end)
end

function M.linksTypedAnnotationsAcrossProjectFiles()
   withProject({
      ["src/model/traits.g.nupp"] = [[
@annotation(targets = {"record"})
record documentation
    @annotationValue
    text: string
end
]],
      ["src/model/user.g.nupp"] = [[
@documentation(text = "A user")
local record User
    id: uint64
end
]],
   }, function(dir)
      local path = dir .. "/src/model/user.g.nupp"
      local env = projectEnv(dir)
      assertEq(#checkFile(env, path), 0,
         "project annotation links must check")
      local formatEnv = projectEnv(dir)
      local formatted, errors = fmt.format(readFile(path), path, {
         annotations = formatEnv.annotations,
         resolveAnnotation = function(name)
            return formatEnv.resolveProjectAnnotation(formatEnv, path, name)
         end,
      })
      assertEq(#errors, 0, "project annotation format diagnostics")
      assert(formatted:find('@documentation("A user")', 1, true), formatted)
   end)
end

function M.rejectsAmbiguousProjectAnnotationNames()
   withProject({
      ["src/a/traits.g.nupp"] = [[
@annotation(targets = {"record"})
record label
    value: string
end
]],
      ["src/b/traits.g.nupp"] = [[
@annotation(targets = {"record"})
record label
    value: string
end
]],
      ["src/use.g.nupp"] = [[
@label(value = "ambiguous")
record Item end
]],
   }, function(dir)
      local diags = checkFile(projectEnv(dir), dir .. "/src/use.g.nupp")
      assertEq(diags[1] and diags[1].code, "NUPP2111",
         "ambiguous annotation name diagnostic")
      assert(diags[1].msg:find("ambiguous project annotation", 1, true),
         diags[1].msg)
   end)
end

-- A global is the one thing still reachable without saying where it came from,
-- and reaching it has to pull in the module that creates it.
function M.cliRunsRequiredModulesAndGlobalStructs()
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["main.nupp"] = [[
local geometry = require("geometry")
local mathutil = require("mathutil")

local doubled: number = mathutil.double(21)
local point: geometry.Point = new geometry.Point(3, 4)
local origin: Origin = new Origin(5)
print(doubled, point.x + point.y, origin.x)
]],
      ["src/mathutil.g.nupp"] = [[
local function double(value: number): number
    return value * 2
end
return { double = double }
]],
      ["src/geometry.g.nupp"] = [[
local geometry = {}

struct geometry.Point
    x: float
    y: float
end

return geometry
]],
      ["src/globals.g.nupp"] = [[
global struct Origin
    x: float
end
]],
   }, function(dir)
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run main.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      local status = os.execute(command)
      assertEq(status, 0, "required project run: " .. readFile(errors))
      assertEq(readFile(output), "42\t7\t5\n", "required project output")
   end)
end

-- Checking a construction is not enough: a record's runtime table lives on the
-- module it was attached to, and if the generator does not learn that, it emits
-- a plain call to a table and the program only fails when it runs.
function M.cliConstructsRecordsFromAnotherModule()
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["main.nupp"] = [[
local shapes = require("geom.shapes")

local p: shapes.Point = new shapes.Point(3, 4)
local named: shapes.Named = new shapes.Named(label = "origin", at = shapes.origin())
print(p.x + p.y, named.label, named.at.x, p is shapes.Point)
]],
      ["src/geom/shapes.g.nupp"] = [[
local shapes = {}

record shapes.Point
    x: number
    y: number
end

record shapes.Named
    label: string
    at: shapes.Point
end

function shapes.origin(): shapes.Point
    return new shapes.Point(0, 0)
end

return shapes
]],
   }, function(dir)
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run main.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      assertEq(os.execute(command), 0,
         "cross-module record run: " .. readFile(errors))
      assertEq(readFile(output), "7\torigin\t0\ttrue\n",
         "cross-module record output")
   end)
end

-- A module may be checked while resolving the consumer and then checked again while
-- building the dependency closure. The nominal survives both passes, so recording
-- the same drop operation twice must be idempotent or one declaration becomes an ambiguous
-- pair merely because the command did more work.
function M.defaultDropOperationSurvivesRepeatedModuleChecks()
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["main.nupp"] = [[
local res = require("res")

do
    local file = res.open()
    print(file.closed)
end
]],
      ["src/res.g.nupp"] = [[
local res = {}

record res.File
    closed: boolean

    @drop
    function close(self)
        self.closed = true
    end
end

@owned
function res.open(): res.File
    return new res.File(closed = false)
end

return res
]],
   }, function(dir)
      local checkErrors = dir .. "/check-errors.txt"
      local checkCommand = ("cd '%s' && '%s/bin/nupp' check --strict main.nupp "
         .. "> /dev/null 2> '%s'"):format(dir, ROOT, checkErrors)
      assertEq(os.execute(checkCommand), 0,
         "the initial check: " .. readFile(checkErrors))

      local buildErrors = dir .. "/build-errors.txt"
      local buildCommand = ("cd '%s' && '%s/bin/nupp' build main.nupp "
         .. "> /dev/null 2> '%s'"):format(dir, ROOT, buildErrors)
      assertEq(os.execute(buildCommand), 0,
         "the dependency recheck: " .. readFile(buildErrors))

      local output = dir .. "/output.txt"
      local runErrors = dir .. "/run-errors.txt"
      local runCommand = ("cd '%s' && '%s/bin/nupp' run main.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, runErrors)
      assertEq(os.execute(runCommand), 0,
         "the cross-module drop operation run: " .. readFile(runErrors))
      assertEq(readFile(output), "false\n", "the resource is usable")
   end)
end

-- A free cleanup is resolved where the producer declares it, registered there, and
-- linked lazily where the consumer discharges it. The private spelling never has to be
-- visible in the consumer.
function M.aPrivateCleanupCrossesIntoAnAutomaticLocal()
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["input.txt"] = "hello\n",
      ["main.nupp"] = [[
local res = require("res")
local use = require("use")

print(use.slurp("input.txt"), res.closed)
]],
      ["src/res.g.nupp"] = [[
local res = {}
res.closed = 0

@drop
local function closeFile(takes file: LuaFile)
    res.closed = res.closed + 1
    file:close()
end

@owned
function res.open(path: string): LuaFile
    local file = io.open(path, "r")
    if not file then error("cannot open " .. path) end
    return file
end

return res
]],
      ["src/use.g.nupp"] = [[
local res = require("res")

local use = {}

function use.slurp(path: string): string
    do
        local file = res.open(path)
        return file:read("*a")
    end
end

return use
]],
   }, function(dir)
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run main.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      assertEq(os.execute(command), 0,
         "cross-module automatic cleanup: " .. readFile(errors))
      assertEq(readFile(output), "hello\n\t1\n", "the private cleanup ran")
   end)
end

function M.aPrivateCleanupCrossesIntoAnExplicitDrop()
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["input.txt"] = "hello\n",
      ["main.nupp"] = [[
local res = require("res")
local use = require("use")

use.touch("input.txt")
print(res.closed)
]],
      ["src/res.g.nupp"] = [[
local res = {}
res.closed = 0

local function closeFile(file: LuaFile)
    res.closed = res.closed + 1
    file:close()
end

@owned(closeFile)
function res.open(path: string): LuaFile
    local file = io.open(path, "r")
    if not file then error("cannot open " .. path) end
    return file
end

return res
]],
      ["src/use.g.nupp"] = [[
local res = require("res")

local use = {}

function use.touch(path: string)
    local file = res.open(path)
    drop(file)
end

return use
]],
   }, function(dir)
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run main.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      assertEq(os.execute(command), 0,
         "cross-module explicit cleanup: " .. readFile(errors))
      assertEq(readFile(output), "1\n", "the private cleanup ran")
   end)
end

-- The name still has to resolve where it was written, which is the one place a
-- misspelling can be fixed.
function M.aMisspelledCleanupIsReportedAtItsDeclaration()
   withProject({
      ["src/res.g.nupp"] = [[
local res = {}

@owned(closeFyle)
function res.open(path: string): LuaFile
    local file = io.open(path, "r")
    if not file then error("cannot open " .. path) end
    return file
end

return res
]],
   }, function(dir)
      local diags = checkFile(projectEnv(dir), dir .. "/src/res.g.nupp")
      assertEq(diags[1] and diags[1].code, "NUPP2615",
         "an unresolvable cleanup is still caught where it is written")
   end)
end

-- A constructor rides the nominal, which is the road a metamethod contract
-- already travels, and lands on the record's runtime table, which is the one
-- thing about a record that a consuming module already reaches. Nothing is
-- registered and nothing is looked up by name at run time.
function M.aConstructorCrossesAModuleBoundary()
   withProject({
      ["src/model.g.nupp"] = [[
local model = {}

record model.Account
    name: string
    balance: number

    constructor(self, name: string, opening: number)
        self.name = name
        self.balance = opening
    end
end

return model
]],
      ["src/use.g.nupp"] = [[
local model = require("model")

local a = new model.Account("Ada", 42)

return a.balance
]],
   }, function(dir)
      local env = projectEnv(dir)
      local path = dir .. "/src/use.g.nupp"
      local parsed = parser.parse(readFile(path), path)
      assertEq(#parsed.errors, 0, "the consumer parses")
      local diags = check.check(parsed, path, env)
      assertEq(#diags, 0, "the consumer checks: "
         .. (diags[1] and diags[1].msg or ""))

      local gen = require("nupp.compiler.gen")
      local code = gen.generate(parsed, path)
      assert(code:find("model.Account.__nuppCtor", 1, true),
         "the call resolves to the minted constructor: " .. code)

      -- and the wrong arguments are still the consumer's problem
      local badPath = dir .. "/src/use.g.nupp"
      local bad = parser.parse(
         'local model = require("model")\n'
         .. 'local a = new model.Account(1, 2)\n'
         .. "return a.balance\n", badPath)
      local badDiags = check.check(bad, badPath, projectEnv(dir))
      assertEq(badDiags[1] and badDiags[1].code, "NUPP2006",
         "a constructor's parameters are checked across the boundary")
   end)
end

-- A default body is emitted once and referenced by each declaration that takes
-- it, so the interface has to be reachable from the implementor's module. That
-- is the whole reason an interface carrying defaults has a runtime table.
function M.aDefaultBodyCrossesAModuleBoundary()
   withProject({
      ["src/greet.g.nupp"] = [[
local greet = {}

interface greet.Greeter
    name: string

    function hello(self): string
        return "hello, " .. self.name
    end
end

return greet
]],
      ["src/use.g.nupp"] = [[
local greet = require("greet")

local record Person is greet.Greeter
    name: string
end

return Person
]],
   }, function(dir)
      local env = projectEnv(dir)
      local path = dir .. "/src/use.g.nupp"
      local parsed = parser.parse(readFile(path), path)
      assertEq(#parsed.errors, 0, "the implementor parses")
      local diags = check.check(parsed, path, env)
      assertEq(#diags, 0, "the implementor checks: "
         .. (diags[1] and diags[1].msg or ""))

      local gen = require("nupp.compiler.gen")
      local code = gen.generate(parsed, path)
      assert(code:find('require("greet").Greeter.hello', 1, true),
         "the default is referenced out of its own module: " .. code)
   end)
end

-- An interface that only declares still emits nothing, so the runtime table is
-- paid for by the feature rather than by every interface.
function M.anInterfaceWithoutDefaultsStaysErased()
   withProject({
      ["src/shape.g.nupp"] = [[
local shape = {}

interface shape.Named
    name: string
end

return shape
]],
   }, function(dir)
      local path = dir .. "/src/shape.g.nupp"
      local parsed = parser.parse(readFile(path), path)
      check.check(parsed, path, projectEnv(dir))
      local gen = require("nupp.compiler.gen")
      local code = gen.generate(parsed, path)
      assert(not code:find("Named", 1, true),
         "an interface with no defaults emits nothing: " .. code)
   end)
end

return M
