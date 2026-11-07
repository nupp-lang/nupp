-- Execute contract fixtures against one real project environment. The compiler
-- and its library modules stay warm; project modules keep a per-case lifetime.
local compile = require("nupp.tools.cli.compile")
local envmod = require("nupp.compiler.project.env")
local runtime = require("nupp.compiler.runtime")

local M = {}

function M.open(root)
    local env

    local function environment()
        env = env or envmod.new(root)
        return env
    end

    local project = {}

    function project.check(files)
        local diagnostics, ok = {}, true
        for _, file in ipairs(files) do
            local result = compile.check(root .. "/" .. file, environment(), {}, diagnostics)
            ok = result ~= nil and ok
        end
        local reported = {}
        for _, diagnostic in ipairs(diagnostics) do
            reported[
                #reported + 1
            ] = {
                file = diagnostic.filename or diagnostic.file or diagnostic.path,
                code = diagnostic.code,
                severity = diagnostic.severity or "error",
                message = diagnostic.msg,
            }
        end

        return ok, reported
    end

    function project.run(file)
        local loadImage = assert(rawget(_G, "__nupp_load_image"), "contract fixtures run on the VM")

        local function compiled(path, e, name, source)
            local strict
            if source ~= nil then
                strict = false
            end

            return compile.image(path, e, name, nil, source, strict)
        end

        local function loadCompiled(code)
            return loadImage(code)
        end

        local remove = runtime.install(
            environment(),
            compiled,
            nil,
            function(path, e)
                return compile.check(path, e, {}) ~= nil
            end,
            loadCompiled
        )
        local ok, problem = pcall(function()
            local path = root .. "/" .. file
            local chunk
            if file:match("%.nupp$") then
                chunk = assert(loadCompiled(assert(compiled(path, environment()))))
            else
                chunk = assert(loadfile(path))
            end
            chunk()
        end)
        remove()
        -- These are fixture modules, never the shared compiler or stdlib.
        for name in pairs(package.loaded) do
            if name:match("^contract%.") or name:match("^example%.") then
                package.loaded[name] = nil
            end
        end
        assert(ok, problem)
    end

    return project
end

return M
