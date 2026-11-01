local test = require("assert")
local environment = require("nupp.compiler.project.env")
local runtime = require("nupp.compiler.runtime")
local compile = require("nupp.tools.cli.compile")
local ROOT = assert(environment.compilerRoot())
local M = {}

local function withLoaders(compiler, loaded, body)
    local before = {}
    for _, loader in ipairs(package.loaders) do
        before[loader] = true
    end
    local env = environment.new(ROOT, {config = {include = {}}, cache = false})
    env.roots = {}
    local remove = runtime.install(env, compiler, nil, nil, loaded)
    local added = {}
    for _, loader in ipairs(package.loaders) do
        if not before[loader] then
            added[#added + 1] = loader
        end
    end
    local ok, reason = pcall(body, added)
    remove()
    assert(ok, reason)
end

function M.finalStandardRootsUseTheExistingCompilerSourceLoader()
    local reached = {}
    local marker = {}
    withLoaders(
        function(path, _, name)
            reached[name] = path
            return "source-token"
        end,
        function()
            return function()
                return marker
            end
        end,
        function(loaders)
            for _, name in ipairs({"types", "own", "utf8", "io.path", "io.uri"}) do
                local loader = loaders[#loaders](name)
                test.equal(type(loader), "function", name)
                test.equal(loader(), marker, name)
                assert(reached[name]:find("/src/", 1, true), reached[name])
            end
            test.equal(loaders[#loaders]("application.nonexistent"), nil)
        end
    )
end

function M.dynamicPublicSimdUsesTheFrozenHostObject()
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local reached, compiledName
    withLoaders(
        function(path, env, name)
            reached, compiledName = path, name
            return compile.image(path, env, name)
        end,
        function(image)
            return loadImage(image)
        end,
        function(loaders)
            local chunk = loaders[1]("simd")
            test.equal(type(chunk), "function")
            test.equal(reached, ROOT .. "/native/crates/vm/lib/nupp/vm/simdbinding.nupp")
            test.equal(compiledName, "nupp.vm.simdbinding")
            local value = chunk()
            test.equal(value, package.loaded["nupp.simd"])
            test.equal(value.vectors(), nil)
            test.raises(
                function()
                    value.species()
                end,
                "SIMD operation requires a statically resolved call"
            )
        end
    )
end

return M
