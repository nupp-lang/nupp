-- Independent module instances for lifecycle fixtures. Each facade retains one
-- provider.
--
-- An instance runs a module's body again with its own `require`, so each one
-- holds its own provider state. On the VM the module's Nupp source is lowered
-- once with its globals read from an environment, which is what that `require`
-- lives in; under LuaJIT the compiled Lua a build left is loaded with one.
local M = {}

local loadImage = rawget(_G, "__nupp_load_image")
local images = {}
local checkEnv = nil

local function vmModule(name)
    local compiled = images[name]
    if compiled then
        return compiled
    end
    -- What an instance requires and the running image does not carry compiles
    -- from source, as a fragment's requires do.
    require("program").installSourceModules()
    local envMod = require("nupp.compiler.project.env")
    local root = envMod.compilerRoot() or "."
    if not checkEnv then
        -- The VM's own implementation of a module comes first, as the image
        -- builder and the runtime loader resolve it.
        checkEnv = envMod.new(root)
        table.insert(checkEnv.roots, 1, root .. "/native/crates/vm/lib")
        table.insert(checkEnv.roots, 1, root .. "/native/crates/vm/decls")
    end
    local path = envMod.findRuntimeModulePath(checkEnv, name)
    if not path then
        error("no Nupp source for " .. name)
    end
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local result = require("nupp.compiler.syntax.parser").parse(source, path)
    assert(#result.errors == 0, "syntax errors in " .. path)
    for _, diagnostic in ipairs(require("nupp.compiler.check").check(result, path, checkEnv, {moduleName = name})) do
        if diagnostic.severity == "error" or not diagnostic.severity then
            error(("%s: %s %s"):format(path, tostring(diagnostic.code), tostring(diagnostic.msg)))
        end
    end
    result.root.vmModuleExports = result.moduleExports
    -- Under a name of its own: an image registers the modules it declares, and an
    -- instance registered as the module itself would answer the process's own
    -- later `require` of it.
    local instanceName = "providerstate:" .. name
    local image = require("nupp.compiler.vm.lower").emit(instanceName, {}, function(candidate)
        return candidate == instanceName and path or nil
    end, function()
        return result.root
    end, true)
    compiled = assert(loadImage(image))
    images[name] = compiled

    return compiled
end

local function filename(name)
    local module = name:gsub("%.", "/")
    for pattern in package.path:gmatch("[^;]+") do
        local path = pattern:gsub("%?", module)
        local file = io.open(path, "rb")
        if file then
            file:close();
            return path
        end
    end
    error("no Lua source for " .. name)
end

local function instance(owned, replacements, preloads, globals)
    local loaded = {}
    local environment = setmetatable({}, {__index = _G})
    for name, value in pairs(globals or {}) do
        environment[name] = value
    end
    environment._G = environment
    environment.package = {loaded = loaded, preload = preloads or {}, path = package.path, cpath = package.cpath}
    environment.require = function(name)
        if loaded[name] ~= nil then
            return loaded[name]
        end
        if replacements and replacements[name] ~= nil then
            return replacements[name]
        end
        local preload = preloads and preloads[name]
        if preload then
            local value = preload()
            loaded[name] = value == nil and true or value
            return loaded[name]
        end
        if not owned[name] then
            return require(name)
        end
        local value
        if loadImage then
            value = vmModule(name)({value = environment})
        else
            local chunk = assert(loadfile(filename(name)))
            setfenv(chunk, environment)
            value = chunk()
        end
        loaded[name] = value == nil and true or value

        return loaded[name]
    end

    return environment.require
end

function M.load(kind, provider)
    local facade = "nupp.io." .. kind
    setmetatable(provider, {
        __index = function(_, name)
            if name == "priority" then
                return nil
            end
            return function()
                error("fixture does not implement " .. name)
            end
        end
    })

    return instance({["nupp.spi"] = true, [facade] = true, ["nupp.io.net.internal"] = true}, {
        ["nupp.spi.index"] = {[facade .. ".spi.Provider"] = {"fixture.provider"}},
        ["fixture.provider"] = provider,
    })(facade)
end

function M.tls(provider)
    setmetatable(provider, {
        __index = function(_, name)
            if name == "priority" then
                return nil
            end
            return function()
                error("fixture does not implement " .. name)
            end
        end
    })

    return instance({["nupp.spi"] = true, ["nupp.io.tls"] = true}, {
        ["nupp.spi.index"] = {["nupp.io.tls.spi.Provider"] = {"fixture.provider"}},
        ["fixture.provider"] = provider,
        ["nupp.io.net"] = {
            pump = function()
            end
        },
        ["nupp.io.net.internal"] = {
            takeStreamHandle = function(stream)
                return stream
            end
        },
    })("nupp.io.tls")
end

function M.browserHttp(memory)
    local name = "nupp.runtime.browser.http"
    return instance({[name] = true}, {["nupp.runtime.browser.memory"] = memory or {}})(name)
end

function M.browserCrypto(response)
    local name = "nupp.runtime.browser.crypto"
    return instance({[name] = true}, {["nupp.runtime.browser.response"] = response})(name)
end

function M.browserSystem(response)
    local name = "nupp.runtime.browser.system"
    return instance({[name] = true}, {["nupp.runtime.browser.response"] = response})(name)
end

function M.browserTime(response, effects, browserHost)
    local name = "nupp.runtime.browser.time"
    return instance(
        {[name] = true},
        {["nupp.runtime.browser.effects"] = effects, ["nupp.runtime.browser.response"] = response,},
        nil,
        {__nuppBrowser = browserHost}
    )(name)
end

function M.browserFiles(memory)
    local name = "nupp.runtime.browser.files"
    return instance({[name] = true}, {["nupp.runtime.browser.memory"] = memory or {}})(name)
end

function M.browserGpu(response, memory)
    local name = "nupp.runtime.browser.webgpu.internal"
    return instance({[name] = true}, {
        ["nupp.runtime.browser.effects"] = {
            request = function(kind, payload, resume)
                response.requests = response.requests or {}
                response.requests[#response.requests + 1] = {kind = kind, payload = payload}
                if payload.operation == "runtime-close" then
                    response.closed = {kind = kind, payload = payload}
                end
                resume({ok = true})

                return function()
                end
            end,
        },
        ["nupp.runtime.browser.memory"] = memory or {},
        ["nupp.runtime.browser.response"] = response,
    })(name)
end

function M.nativeHttp(native)
    local name = "nupp.io.http.internal.transport"
    return instance({[name] = true}, {["nupp.runtime.native"] = native})(name)
end

function M.nativeHttpProvider(transport)
    local name = "nupp.runtime.provider.nativehttp"
    return instance({[name] = true}, {["nupp.io.http.internal.transport"] = transport})(name)
end

function M.nativeGpu(native)
    local name = "nupp.runtime.provider.nativegpu"
    return instance({[name] = true, ["nupp.runtime.provider.nativegpurelease"] = true}, {
        ["nupp.runtime.native"] = native,
    })(name)
end

-- Each fixture owns an ordinary immutable discovery index and module cache.
function M.family(kind, providers)
    local facade = "nupp." .. kind
    local names, preloads = {}, {}
    for index, provider in ipairs(providers or {}) do
        local name = "fixture.provider" .. index
        names[index] = name
        preloads[name] = type(provider) == "function" and provider or function()
            return provider
        end
    end
    local load = instance(
        {["nupp.spi"] = true, [facade] = true, ["nupp.runtime.provider." .. kind] = true},
        {["nupp.spi.index"] = {[facade .. ".spi.Provider"] = names},},
        preloads
    )
    local spi, counts = load("nupp.spi"), {resolutions = 0}
    local original = spi.load
    spi.load = function(interface)
        counts.resolutions = counts.resolutions + 1
        return original(interface)
    end

    return load, counts
end

M.instance = instance

return M
