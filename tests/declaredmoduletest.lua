local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")
local header = require("nupp.compiler.header")
local incremental = require("nupp.compiler.incremental")
local runtime = require("nupp.compiler.runtime")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s: want %s, got %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
   end
end

local function diagnosticContaining(diags, text)
   for _, diag in ipairs(diags) do
      if diag.msg and diag.msg:find(text, 1, true) then
         return diag
      end
   end
end

local function writeFile(path, text)
   local parent = assert(path:match("^(.*)[/\\]"))
   assert(os.execute("mkdir -p '" .. parent .. "'") == 0)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function readFile(path)
   local file = assert(io.open(path, "rb"))
   local text = file:read("*a")
   file:close()
   return text
end

local function withProject(files, callback)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   for path, source in pairs(files) do
      writeFile(dir .. "/" .. path, source)
   end
   local ok, result = pcall(callback, dir)
   os.execute("rm -rf '" .. dir .. "'")
   if not ok then error(result, 0) end
   return result
end

local function projectEnv(dir)
   return envMod.new(dir, {config = {include = {"src"}}})
end

local function compile(path, env)
   local result = parser.parse(readFile(path), path)
   if #result.errors > 0 then return nil, result.errors[1].msg end
   local diags = check.check(result, path, env)
   if #diags > 0 then return nil, diags[1].msg end
   local code, generated = gen.generate(result, path)
   if #generated > 0 then return nil, generated[1].msg end
   return code
end

local M = {}

function M.parsesChecksAndRunsDeclaredExports()
   withProject({
      ["src/mathbox.nupp"] = [[
module mathbox

export const answer: integer = 42

export record Box
   value: integer
end

export function twice(value: integer): integer
   return value * 2
end


export function box(value: integer): Box
   return new Box(value = value)
end
]],
   }, function(dir)
      local path = dir .. "/src/mathbox.nupp"
      local env = projectEnv(dir)
      local parsed = parser.parse(readFile(path), path)
      assertEq(#parsed.errors, 0, "declared syntax")
      local diags, moduleType, exports = check.check(parsed, path, env)
      assertEq(#diags, 0, diags[1] and diags[1].msg)
      assert(exports.values.answer, "constant is in the value interface")
      assert(exports.values.twice, "function is in the value interface")
      assert(exports.types.Box, "record is in the type interface")
      assert(exports.values.Box, "record constructor is in the value interface")
      assert(moduleType, "declared module has a boundary type")

      package.loaded.mathbox = nil
      local removeLoader = runtime.install(env, compile)
      local mathbox = require("mathbox")
      removeLoader()
      package.loaded.mathbox = nil
      assertEq(mathbox.answer, 42)
      assertEq(mathbox.twice(21), 42)
      assertEq(mathbox.box(42).value, 42)
   end)
end

function M.rejectsWrongCanonicalNameAndTopLevelReturn()
   withProject({
      ["src/right.nupp"] = "module wrong\nreturn {}\n",
   }, function(dir)
      local path = dir .. "/src/right.nupp"
      local parsed = parser.parse(readFile(path), path)
      local diags = check.check(parsed, path, projectEnv(dir))
      assert(diags[1] and diags[1].msg:find("canonical module name", 1, true))
      local sawReturn = false
      for _, diag in ipairs(diags) do
         sawReturn = sawReturn or diag.msg:find("no top-level return", 1, true) ~= nil
      end
      assert(sawReturn, "declared modules reject a return table")
   end)
end

function M.recursiveChecksUsePublishedInterfacesInsteadOfAny()
   withProject({
      ["src/a.nupp"] = [[
module a
const b = require("b")
export function fromA(value: integer): integer
   return b.fromB(value)
end
]],
      ["src/b.nupp"] = [[
module b
const a = require("a")
export function fromB(value: integer): integer
   return value + 1
end
export function throughA(value: integer): integer
   return a.fromA(value)
end
]],
   }, function(dir)
      local inc = incremental.new(dir, {config = {include = {"src"}}})
      local checked = inc.checkFile(dir .. "/src/a.nupp")
      assertEq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
      assert(checked.exports.values.fromA ~= nil, "the recursive interface keeps its function")

      package.loaded.a = nil
      package.loaded.b = nil
      local env = projectEnv(dir)
      local removeLoader = runtime.install(env, compile)
      local a = require("a")
      removeLoader()
      package.loaded.a = nil
      package.loaded.b = nil
      assertEq(a.fromA(41), 42, "benign function cycle")
   end)
end

function M.typeSelectionsAreErasedButStillResolveTheInterface()
   withProject({
      ["src/model.nupp"] = [[
module model
export record Point
   x: number
end
]],
      ["src/use.nupp"] = [[
module use
const {type Point as LocalPoint} = require("model")
export function accept(value: LocalPoint): nil
end
]],
   }, function(dir)
      local inc = incremental.new(dir, {config = {include = {"src"}}})
      local checked = inc.checkFile(dir .. "/src/use.nupp")
      assertEq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
      local code, diags = gen.generate(checked.result, dir .. "/src/use.nupp")
      assertEq(#diags, 0, diags[1] and diags[1].msg)
      assert(not code:find('require("model")', 1, true), "a type-only selection emits no require")
   end)
end

function M.qualifiedNamespacesSelectOneHiddenDirectRequire()
   withProject({
      ["src/tecs/world/query.nupp"] = [[
module tecs.world.query
export function each(value: integer): integer
   return value + 1
end
]],
      ["src/use.nupp"] = [[
module use
export function answer(): integer
   return tecs.world.query.each(41) + tecs.world.query.each(0)
end
]],
   }, function(dir)
      local inc = incremental.new(dir, {config = {include = {"src"}}})
      local checked = inc.checkFile(dir .. "/src/use.nupp")
      assertEq(#checked.diags, 0, checked.diags[1] and checked.diags[1].msg)
      local code, diags = gen.generate(checked.result, dir .. "/src/use.nupp")
      assertEq(#diags, 0, diags[1] and diags[1].msg)
      local _, count = code:gsub('require%("tecs.world.query"%)', "")
      assertEq(count, 1, "one hidden module binding")
      assert(not code:find("tecs.world.query.each", 1, true), "qualified path is lowered away")

      package.loaded.use = nil
      package.loaded["tecs.world.query"] = nil
      local env = projectEnv(dir)
      local removeLoader = runtime.install(env, compile)
      local use = require("use")
      removeLoader()
      package.loaded.use = nil
      package.loaded["tecs.world.query"] = nil
      assertEq(use.answer(), 43, "qualified module call")
   end)
end

function M.registryRejectsReservedAndChildExportCollisions()
   withProject({
      ["src/nupp/pin.nupp"] = "module nupp.pin\nexport const value: integer = 1\n",
      ["src/pkg.nupp"] = "module pkg\nexport const child: integer = 1\n",
      ["src/pkg/child.nupp"] = "module pkg.child\nexport const value: integer = 2\n",
   }, function(dir)
      local inc = incremental.new(dir, {config = {include = {"src"}}})
      local reserved = inc.checkFile(dir .. "/src/nupp/pin.nupp").diags
      assert(diagnosticContaining(reserved, "compiler-owned"), "reserved compiler path")
      local collision = inc.checkFile(dir .. "/src/pkg/child.nupp").diags
      local found = diagnosticContaining(collision, "collides with export")
      assert(found, "child/export collision")
      assert(found.related and found.related[1], "collision points at the export")
   end)
end

function M.exportedFunctionHeadersIgnorePrivateBodies()
   local before = parser.parse([[
module sample
export function answer(value: integer): integer
   return value + 1
end
]], "sample.nupp")
   local after = parser.parse([[
module sample
export function answer(value: integer): integer
   return value + 2
end
]], "sample.nupp")
   local left = header.of("sample.nupp", "sample", before)
   local right = header.of("sample.nupp", "sample", after)
   assertEq(left.declarations[1].signature, right.declarations[1].signature,
      "body-only edits preserve the exported interface header")
end

function M.moduleWordsRemainContextualNames()
   local parsed = parser.parse("export = function() end\nexport()\nmodule('legacy')\n", "names.lua")
   assertEq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
   assertEq(parsed.root.blocks[1].stats[1].kind, "assignStmt")
   assertEq(parsed.root.blocks[1].stats[2].kind, "callStmt")
   assertEq(parsed.root.blocks[1].stats[3].kind, "callStmt")
end

function M.eagerCallsIntoAnInitializingModuleAreRejected()
   withProject({
      ["src/a.nupp"] = [[
module a
const b = require("b")
export function fromA(value: integer): integer
   return value + 1
end
]],
      ["src/b.nupp"] = [[
module b
const a = require("a")
const tooEarly: integer = a.fromA(1)
export function fromB(value: integer): integer
   return value + tooEarly
end
]],
   }, function(dir)
      local inc = incremental.new(dir, {config = {include = {"src"}}})
      inc.checkFile(dir .. "/src/a.nupp")
      local diags = inc.checkFile(dir .. "/src/b.nupp").diags
      assert(diagnosticContaining(diags, "eager module cycle"), "eager cycle diagnostic")
   end)
end

return M
