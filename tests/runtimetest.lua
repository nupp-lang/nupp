local parser = require("compiler.parser")
local check = require("fragment")
local gen = require("compiler.gen")
local envMod = require("compiler.env")
local runtime = require("compiler.runtime")

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
   for path, text in pairs(files) do
      writeFile(dir .. "/" .. path, text)
   end
   local ok, result = pcall(callback, dir)
   os.execute("rm -rf '" .. dir .. "'")
   if not ok then error(result, 0) end
   return result
end

local function compile(path, env)
   local result = parser.parse(readFile(path), path)
   if #result.errors > 0 then return nil, "syntax errors" end
   local diags = check.check(result, path, env)
   if #diags > 0 then return nil, "type errors" end
   local code, genDiags = gen.generate(result, path)
   if #genDiags > 0 then return nil, "code generation errors" end
   return code
end

local function projectEnv(dir)
   return envMod.new(dir, { config = { include = { "src" } } })
end

local M = {}

function M.loadsLjppFromProjectRoots()
   withProject({
      ["src/runtimeanswer.nupp"] = [[
local M = {}
function M.double(value: number): number return value * 2 end
return M
]],
   }, function(dir)
      package.loaded.runtimeanswer = nil
      local removeLoader = runtime.install(projectEnv(dir), compile)
      local answer = require("runtimeanswer")
      removeLoader()
      package.loaded.runtimeanswer = nil
      assertEq(answer.double(21), 42, "required nupp module")
   end)
end

function M.loadsInitModulesOnlyOnce()
   withProject({
      ["src/runtimefolder/init.nupp"] = [[
_G.runtimeFolderLoads = (_G.runtimeFolderLoads or 0) + 1
return { loads = _G.runtimeFolderLoads }
]],
   }, function(dir)
      package.loaded.runtimefolder = nil
      _G.runtimeFolderLoads = nil
      local removeLoader = runtime.install(projectEnv(dir), compile)
      local first = require("runtimefolder")
      local second = require("runtimefolder")
      removeLoader()
      package.loaded.runtimefolder = nil
      _G.runtimeFolderLoads = nil
      assert(first == second, "require must return the cached module")
      assertEq(first.loads, 1, "init module execution count")
   end)
end

function M.preservesPreloadAndPlainLuaLoaders()
   withProject({
      ["src/runtimepreferred.nupp"] = "return 'nupp'\n",
      ["src/runtimeplain.lua"] = "return 'lua'\n",
   }, function(dir)
      package.loaded.runtimepreferred = nil
      package.loaded.runtimeplain = nil
      package.preload.runtimepreferred = function() return "preload" end
      local removeLoader = runtime.install(projectEnv(dir), compile)
      local preferred = require("runtimepreferred")
      local plain = require("runtimeplain")
      removeLoader()
      package.preload.runtimepreferred = nil
      package.loaded.runtimepreferred = nil
      package.loaded.runtimeplain = nil
      assertEq(preferred, "preload", "package.preload priority")
      assertEq(plain, "lua", "plain Lua project module")
   end)
end

function M.preservesRequireCycleErrors()
   withProject({
      ["src/runtimecyclea.nupp"] = [[
local b = require("runtimecycleb")
return { b = b }
]],
      ["src/runtimecycleb.nupp"] = [[
local a = require("runtimecyclea")
return { a = a }
]],
   }, function(dir)
      package.loaded.runtimecyclea = nil
      package.loaded.runtimecycleb = nil
      local removeLoader = runtime.install(projectEnv(dir), compile)
      local ok, err = pcall(require, "runtimecyclea")
      removeLoader()
      package.loaded.runtimecyclea = nil
      package.loaded.runtimecycleb = nil
      assert(not ok, "cyclic require must fail with Lua's normal loop error")
      assert(tostring(err):find("loop or previous error", 1, true),
         "unexpected cyclic require error: " .. tostring(err))
   end)
end

function M.cliRunLoadsRequiredLjppModules()
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["main.nupp"] = [[
local answer = require("runtimeclianswer")
print(answer.value)
]],
      ["src/runtimeclianswer.nupp"] = "return { value = 42 }\n",
   }, function(dir)
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run main.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      local status = os.execute(command)
      assertEq(status, 0, "nupp run exit status: " .. readFile(errors))
      assertEq(readFile(output), "42\n", "nupp run module output")
   end)
end

return M
