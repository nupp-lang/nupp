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

    local function absolute(path)
        if path:match("^/") or path:match("^%a:[/\\]") then
            return path
        end
        return root .. "/" .. path
    end

    function project.check(files)
        local diagnostics, ok = {}, true
        for _, file in ipairs(files) do
            local result = compile.check(absolute(file), environment(), {}, diagnostics)
            ok = result ~= nil and ok
        end

        return ok, require("nupp.tools.cli.report").diagnosticValues(diagnostics)
    end

    function project.run(file, capturePrint)
        local loadImage = rawget(_G, "__nupp_load_image")
        local settings = not loadImage and compile.settings({}) or nil

        local function compiled(path, e, name, source)
            local strict
            if source ~= nil then
                strict = false
            end
            if loadImage then
                return compile.image(path, e, name, nil, source, strict)
            end

            return compile.module(path, e, settings, name, source, strict)
        end

        local function loadCompiled(code, path)
            if loadImage then
                return loadImage(code)
            end
            return loadstring(code, "@" .. path)
        end

        local remove = runtime.install(
            environment(),
            compiled,
            nil,
            function(path, e)
                return compile.check(path, e, {}) ~= nil
            end,
            loadImage and loadCompiled or nil
        )
        local printed, originalPrint = {}, print
        if capturePrint then
            print = function(...)
                local values = {}
                for index = 1, select("#", ...) do
                    values[index] = tostring(select(index, ...))
                end
                printed[#printed + 1] = table.concat(values, "\t") .. "\n"
            end
        end
        local ok, problem = pcall(function()
            local path = absolute(file)
            local chunk
            if file:match("%.nupp$") then
                chunk = assert(loadCompiled(assert(compiled(path, environment())), path))
            else
                chunk = assert(loadfile(path))
            end
            chunk()
        end)
        print = originalPrint
        remove()
        -- These are fixture modules, never the shared compiler or stdlib.
        for name in pairs(package.loaded) do
            if name:match("^contract%.") or name:match("^example%.") then
                package.loaded[name] = nil
            end
        end
        assert(ok, problem)

        return table.concat(printed)
    end

    return project
end

return M
