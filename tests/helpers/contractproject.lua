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
        if capturePrint then
            -- VM print calls target the runtime directly. Capture real child output.
            local executable = require("helpers.paths").absoluteTests .. "/../bin/nupp"
            local status, output = require("nupp.compiler.process").capture({executable, "run", absolute(file)}, {
                cwd = root
            })
            assert(status == 0, output)
            return output
        end
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
            local path = absolute(file)
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

        return ""
    end

    return project
end

return M
