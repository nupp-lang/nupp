local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")
local runtime = require("nupp.compiler.runtime")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local cwdPipe = assert(io.popen("pwd"))
local currentDir = assert(cwdPipe:read("*l"))
cwdPipe:close()
local ROOT = HERE:sub(1, 1) == "/" and (HERE .. "/..") or (currentDir .. "/" .. HERE .. "/..")

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
    if not ok then
        error(result, 0)
    end

    return result
end

local function compile(path, env, name)
    local result = parser.parse(readFile(path), path)
    if #result.errors > 0 then
        return nil, "syntax errors"
    end
    local diags = check.check(result, path, env)
    if #diags > 0 then
        return nil, "type errors"
    end
    local ok, image = pcall(program.image, result, name, path)
    if not ok then
        return nil, "lowering errors: " .. tostring(image)
    end

    return image
end

-- The project loader, running what `compile` lowered as a VM image.
local function install(env, compiler)
    return runtime.install(env, compiler, nil, nil, function(image)
        return rawget(_G, "__nupp_load_image")(image)
    end)
end

local function projectEnv(dir)
    return envMod.new(dir, {config = {include = {"src"}}})
end

local M = {}

function M.loadsLjppFromProjectRoots()
    withProject(
        {
            [
                "src/runtimeanswer.nupp"
            ] = [[
local M = {}
function M.double(value: number): number return value * 2 end
return M
]],
        },
        function(dir)
            package.loaded.runtimeanswer = nil
            local removeLoader = install(projectEnv(dir), compile)
            local answer = require("runtimeanswer")
            removeLoader()
            package.loaded.runtimeanswer = nil
            testAssert.equal(answer.double(21), 42, "required nupp module")
        end
    )
end

function M.loadsInitModulesOnlyOnce()
    withProject(
        {
            [
                "src/runtimefolder/init.nupp"
            ] = [[
_G.runtimeFolderLoads = (_G.runtimeFolderLoads or 0) + 1
return { loads = _G.runtimeFolderLoads }
]],
        },
        function(dir)
            package.loaded.runtimefolder = nil
            _G.runtimeFolderLoads = nil
            local removeLoader = install(projectEnv(dir), compile)
            local first = require("runtimefolder")
            local second = require("runtimefolder")
            removeLoader()
            package.loaded.runtimefolder = nil
            _G.runtimeFolderLoads = nil
            assert(first == second, "require must return the cached module")
            testAssert.equal(first.loads, 1, "init module execution count")
        end
    )
end

function M.preservesPreloadAndPlainLuaLoaders()
    withProject(
        {["src/runtimepreferred.nupp"] = "return 'nupp'\n", ["src/runtimeplain.lua"] = "return 'lua'\n",},
        function(dir)
            package.loaded.runtimepreferred = nil
            package.loaded.runtimeplain = nil
            package.preload.runtimepreferred = function()
                return "preload"
            end
            local removeLoader = install(projectEnv(dir), compile)
            local preferred = require("runtimepreferred")
            local plain = require("runtimeplain")
            removeLoader()
            package.preload.runtimepreferred = nil
            package.loaded.runtimepreferred = nil
            package.loaded.runtimeplain = nil
            testAssert.equal(preferred, "preload", "package.preload priority")
            testAssert.equal(plain, "lua", "plain Lua project module")
        end
    )
end

function M.preservesRequireCycleErrors()
    withProject(
        {
            ["src/runtimecyclea.nupp"] = [[
local b = require("runtimecycleb")
return { b = b }
]],
            ["src/runtimecycleb.nupp"] = [[
local a = require("runtimecyclea")
return { a = a }
]],
        },
        function(dir)
            package.loaded.runtimecyclea = nil
            package.loaded.runtimecycleb = nil
            local removeLoader = install(projectEnv(dir), compile)
            local ok, err = pcall(require, "runtimecyclea")
            removeLoader()
            package.loaded.runtimecyclea = nil
            package.loaded.runtimecycleb = nil
            assert(not ok, "cyclic require must fail with Lua's normal loop error")
            assert(
                tostring(err):find("loop or previous error", 1, true),
                "unexpected cyclic require error: " .. tostring(err)
            )
        end
    )
end

function M.declinesRequiresIssuedWhileCompiling()
    withProject(
        {["src/runtimemain.nupp"] = "return { ok = true }\n", ["src/runtimelazy.lua"] = "return 'from-project'\n",},
        function(dir)
            package.loaded.runtimemain = nil
            package.loaded.runtimelazy = nil
            local midCompile
            local removeLoader = install(projectEnv(dir), function(path, env, name)
                -- The compiler lazily requires pieces of itself while compiling. Such
                -- a require must fall through to the chain behind this loader, even
                -- when the project could resolve the name, or the loader re-enters
                -- the very compile that is computing the module's exports.
                local ok, result = pcall(require, "runtimelazy")
                midCompile = ok and result or "declined"
                return compile(path, env, name)
            end)
            local main = require("runtimemain")
            removeLoader()
            package.loaded.runtimemain = nil
            package.loaded.runtimelazy = nil
            testAssert.equal(main.ok, true, "compiled module loads")
            testAssert.equal(midCompile, "declined", "a require issued while compiling must not re-enter the loader")
        end
    )
end

function M.cliRunLoadsStdlibFromALuaEntry()
    withProject(
        {
            ["nupp.lua"] = "return { include = { 'src' } }\n",
            ["main.lua"] = [[
local time = require("nupp.time")
print(type(time.now()))
]],
        },
        function(dir)
            local output = dir .. "/output.txt"
            local errors = dir .. "/errors.txt"
            local command = (
                "cd '%s' && '%s/bin/nupp' run main.lua " .. "> '%s' 2> '%s'"
            ):format(dir, ROOT, output, errors)
            local status = os.execute(command)
            testAssert.equal(status, 0, "nupp run stdlib exit status: " .. readFile(errors))
            testAssert.equal(readFile(output), "number\n", "nupp run stdlib output")
        end
    )
end

function M.cliRunLoadsRequiredLjppModules()
    withProject(
        {
            ["nupp.lua"] = "return { include = { 'src' } }\n",
            ["main.nupp"] = [[
local answer = require("runtimeclianswer")
print(answer.value)
]],
            ["src/runtimeclianswer.nupp"] = "return { value = 42 }\n",
        },
        function(dir)
            local output = dir .. "/output.txt"
            local errors = dir .. "/errors.txt"
            local command = (
                "cd '%s' && '%s/bin/nupp' run main.nupp " .. "> '%s' 2> '%s'"
            ):format(dir, ROOT, output, errors)
            local status = os.execute(command)
            testAssert.equal(status, 0, "nupp run exit status: " .. readFile(errors))
            testAssert.equal(readFile(output), "42\n", "nupp run module output")
        end
    )
end

-- A `.lua` dependency whose body breaks the contract its annotations declare is
-- refused at run, the way a `.nupp` dependency with an error is: strict code was
-- checked against the claim, so running the body would hand it the wrong value.
function M.cliRunRefusesALuaDependencyThatBreaksItsContract()
    withProject(
        {
            ["nupp.lua"] = "return { include = { 'src' } }\n",
            [
                "main.nupp"
            ] = [[
local cats = require("runtimelyingcats")
local name: string = cats.name()
print(name:upper())
]],
            [
                "src/runtimelyingcats.lua"
            ] = [[
local M = {}
---@return string
function M.name()
   local v = 42
   return v
end
return M
]],
        },
        function(dir)
            local output = dir .. "/output.txt"
            local errors = dir .. "/errors.txt"
            local command = (
                "cd '%s' && '%s/bin/nupp' run main.nupp " .. "> '%s' 2> '%s'"
            ):format(dir, ROOT, output, errors)
            local status = os.execute(command)
            assert(status ~= 0, "a lying .lua dependency ran")
            local said = readFile(errors)
            assert(said:find("NUPP2002", 1, true), "the contract violation was not reported: " .. said)
            assert(
                said:find("error checking lua module 'runtimelyingcats'", 1, true),
                "the run was not refused for the dependency: " .. said
            )
            testAssert.equal(readFile(output), "", "the program ran anyway")
        end
    )
end

-- The loader compiles a dependency under the path the searcher found, which a root
-- of "." spelled "./src/...", while the check that loaded its types for the entry
-- had spelled it "src/...". Taken for two files, the module's interface was
-- declared twice into one type, and a record claiming it was then held to a self
-- binder the interface no longer carried.
function M.cliRunCompilesAModuleClaimingAnInterfaceItDeclares()
    withProject(
        {
            ["nupp.lua"] = "return { include = { 'src' } }\n",
            ["main.nupp"] = [[
local claims = require("runtimeclaims")
print(claims.make():label())
]],
            [
                "src/runtimeclaims.nupp"
            ] = [[
module runtimeclaims

export interface Labeled
    label: function(self): string
end

local record Impl is Labeled
    text: string
    function label(self): string
        return self.text
    end
end

export function make(): Labeled
    return new Impl(text = "claimed")
end
]],
        },
        function(dir)
            local output = dir .. "/output.txt"
            local errors = dir .. "/errors.txt"
            local command = (
                "cd '%s' && '%s/bin/nupp' run main.nupp " .. "> '%s' 2> '%s'"
            ):format(dir, ROOT, output, errors)
            local status = os.execute(command)
            assert(status == 0, "the run was refused: " .. readFile(errors))
            testAssert.equal(readFile(output), "claimed\n", "the claiming module did not run")
        end
    )
end

function M.cliRunLoadsCrossModuleDeriveDependencies()
    withProject(
        {
            ["nupp.lua"] = "return { include = { 'src' } }\n",
            [
                "main.nupp"
            ] = [[
local models = require("runtime_derive_models")
@derive(nupp.derive.Debug)
local record Outer inner: models.Inner end
local value = new Outer(inner = new models.Inner())
print(value:debug())
local out = require("nupp.text").newBuffer()
local writer = nupp.codec.json.newWriter(out)
require("nupp.serde.json").writeValue(nupp.serde.binding(Outer), value, writer)
writer:close()
print(out:tostring())
]],
            [
                "src/runtime_derive_models.nupp"
            ] = [[
local models = {}
@derive(nupp.derive.Debug)
record models.Inner value: integer = 0 end
return models
]],
        },
        function(dir)
            package.loaded.runtime_derive_models = nil
            local output = dir .. "/output.txt"
            local errors = dir .. "/errors.txt"
            local command = (
                "cd '%s' && '%s/bin/nupp' run main.nupp " .. "> '%s' 2> '%s'"
            ):format(dir, ROOT, output, errors)
            local status = os.execute(command)
            package.loaded.runtime_derive_models = nil
            testAssert.equal(status, 0, "nupp run derive exit status: " .. readFile(errors))
            testAssert.equal(
                readFile(output),
                "Outer { inner = Inner { value = 0 } }\n{\"inner\":{\"value\":0}}\n",
                "nupp run derive output"
            )
        end
    )
end

return M
