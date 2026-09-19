-- Independent module instances for lifecycle fixtures. Each facade retains one
-- provider.
local M = {}

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

local function instance(owned, replacements, preloads)
    local loaded = {}
    local environment = setmetatable({}, {__index = _G})
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
        local chunk = assert(loadfile(filename(name)))
        setfenv(chunk, environment)
        local value = chunk()
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

function M.browserHttp(memory)
    local name = "nupp.runtime.browser.http"
    return instance({[name] = true}, {["nupp.runtime.wasm"] = memory or {}})(name)
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
