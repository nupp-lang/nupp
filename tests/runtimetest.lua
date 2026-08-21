local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local envMod = require("nupp.compiler.env")
local runtime = require("nupp.compiler.runtime")

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

function M.cliRunLoadsCrossModuleDeriveDependencies()
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["main.nupp"] = [[
local models = require("runtime_derive_models")
@derive(nupp.derive.Debug, nupp.derive.JSON)
local record Outer inner: models.Inner end
local value = new Outer(inner = new models.Inner())
print(value:debug())
local out = string.buffer.new()
local writer = nupp.data.json.writer(out)
value:writeJSON(writer)
writer:close()
print(out:tostring())
]],
      ["src/runtime_derive_models.nupp"] = [[
local models = {}
@derive(nupp.derive.Debug, nupp.derive.JSON)
record models.Inner value: integer = 0 end
return models
]],
   }, function(dir)
      package.loaded.runtime_derive_models = nil
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run main.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      local status = os.execute(command)
      package.loaded.runtime_derive_models = nil
      assertEq(status, 0, "nupp run derive exit status: " .. readFile(errors))
      assertEq(readFile(output),
         "Outer { inner = Inner { value = 0 } }\n{\"inner\":{\"value\":0}}\n",
         "nupp run derive output")
   end)
end

function M.cliWatchCommitsAndKeepsTheLastGoodGeneration()
   local function watched(body)
      return table.concat({
         "local M = {}",
         "function M.value(): integer",
         "   " .. body,
         "end",
         "return M",
         "",
      }, "\n")
   end
   local versionTwo = string.format("%q", watched("return 2"))
   local rejected = string.format("%q", watched("return 'bad'"))
   local structural = string.format("%q", "local marker: integer = 1\n" .. watched("return 3"))
   withProject({
      ["nupp.lua"] = "return { include = { 'src' } }\n",
      ["writer.lua"] = [[
return function(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end
]],
      ["src/watched.nupp"] = watched("return 1"),
      ["main.g.nupp"] = table.concat({
         "local watched = require('watched')",
         "local write = require('writer')",
         "nupp.hotreload.poll()",
         "print(watched.value())",
         "write('src/watched.nupp', " .. versionTwo .. ")",
         "nupp.hotreload.poll()",
         "print(watched.value())",
         "write('src/watched.nupp', " .. rejected .. ")",
         "nupp.hotreload.poll()",
         "print(watched.value())",
         "write('src/watched.nupp', " .. structural .. ")",
         "nupp.hotreload.poll()",
         "print(watched.value())",
         "",
      }, "\n"),
   }, function(dir)
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run --watch main.g.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      local status = os.execute(command)
      local stderr = readFile(errors)
      assertEq(status, 0, "nupp run --watch exit status: " .. stderr)
      assertEq(readFile(output), "1\n2\n2\n2\n", "watch generation output")
      assert(stderr:find("committed hot generation 2", 1, true), stderr)
      assert(stderr:find("NUPP2002", 1, true), stderr)
      assert(stderr:find("generation 2 remains running", 1, true), stderr)
      assert(stderr:find("NUPP5001", 1, true), stderr)
      assert(stderr:find("top-level structure changed in watched", 1, true), stderr)
   end)
end

function M.cliWatchRejectsOptimizedGeneration()
   withProject({["main.nupp"] = "print(1)\n"}, function(dir)
      local output = dir .. "/output.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run --watch -O1 main.nupp "
         .. "> '%s' 2>&1"):format(dir, ROOT, output)
      local status = os.execute(command)
      assert(status ~= 0, "optimized watch command must fail")
      assert(readFile(output):find("--watch supports -O0 only", 1, true), readFile(output))
   end)
end

function M.cliWatchObservesHeaderOnlyEdits()
   withProject({
      ["api.h"] = "int hot_watch_header(void);\n",
      ["writer.lua"] = [[
return function(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end
]],
      ["main.g.nupp"] = table.concat({
         "local api = cheader('api.h')",
         "local write = require('writer')",
         "nupp.hotreload.poll()",
         "write('api.h', '/* comment */\\nint hot_watch_header(void);\\n')",
         "print(nupp.hotreload.poll().kind)",
         "write('api.h', 'long hot_watch_header(void);\\n')",
         "print(nupp.hotreload.poll().kind)",
         "return api",
         "",
      }, "\n"),
   }, function(dir)
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run --watch main.g.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      local status = os.execute(command)
      local stderr = readFile(errors)
      assertEq(status, 0, "header watch exit status: " .. stderr)
      assertEq(readFile(output), "no-change\nrestart-required\n")
      assert(stderr:find("header api.h at", 1, true), stderr)
   end)
end

function M.cliWatchRequiresRestartForMappedNativeReplacement()
   local ffi = require("ffi")
   if ffi.os == "Windows" or os.execute("cc --version >/dev/null 2>&1") ~= 0 then
      return require("assert").skip("a POSIX C compiler is unavailable")
   end
   withProject({
      ["first.c"] = "int hot_native_value(void) { return 1; }\n",
      ["second.c"] = "int hot_native_value(void) { return 2; }\n",
      ["replace.lua"] = "return function(from, to) assert(os.rename(from, to)) end\n",
   }, function(dir)
      local extension = ffi.os == "OSX" and ".dylib" or ".so"
      local current = "libmini" .. extension
      local replacement = "libmini-next" .. extension
      local flags = ffi.os == "OSX" and "-dynamiclib" or "-shared -fPIC"
      assertEq(os.execute(("cc %s -o '%s/%s' '%s/first.c'"):format(
         flags, dir, current, dir)), 0, "compile first library")
      assertEq(os.execute(("cc %s -o '%s/%s' '%s/second.c'"):format(
         flags, dir, replacement, dir)), 0, "compile replacement library")
      writeFile(dir .. "/nupp.lua", ("return { hotreload = { libraries = { mini = %q } } }\n")
         :format(current))
      writeFile(dir .. "/main.g.nupp", table.concat({
         "cdef function hot_native_value(): int32 from 'mini'",
         "local replace = require('replace')",
         "nupp.hotreload.poll()",
         "print(hot_native_value())",
         ("replace(%q, %q)"):format(replacement, current),
         "print(nupp.hotreload.poll().kind)",
         "",
      }, "\n"))
      local output = dir .. "/output.txt"
      local errors = dir .. "/errors.txt"
      local command = ("cd '%s' && '%s/bin/nupp' run --watch main.g.nupp "
         .. "> '%s' 2> '%s'"):format(dir, ROOT, output, errors)
      local status = os.execute(command)
      local stderr = readFile(errors)
      assertEq(status, 0, "native watch exit status: " .. stderr)
      assertEq(readFile(output), "1\nrestart-required\n")
      assert(stderr:find("native artifact for mini at", 1, true), stderr)
   end)
end

return M
