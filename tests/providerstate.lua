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

local function instance(owned, replacements)
    local loaded = {}
    local environment = setmetatable({}, {__index = _G})
    environment._G = environment
    environment.package = {loaded = loaded, preload = {}, path = package.path, cpath = package.cpath}
    environment.require = function(name)
        if loaded[name] ~= nil then
            return loaded[name]
        end
        if replacements and replacements[name] ~= nil then
            return replacements[name]
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
    local contract = "nupp.runtime.services." .. kind
    local facade = "nupp.io." .. kind
    local load = instance({
        ["nupp.services"] = true,
        [contract] = true,
        [facade] = true,
        ["nupp.io.net.internal"] = true
    })
    local service = load(contract).service
    for _, member in ipairs(service.members or {}) do
        if provider[member.name] == nil then
            local name = member.name
            provider[name] = function()
                error("fixture does not implement " .. name)
            end
        end
    end
    service:register("fixture", function()
        return provider
    end)
    service:select("fixture")

    return load(facade)
end

function M.browserHttp(memory)
    local name = "nupp.runtime.browser.http"
    return instance({[name] = true}, {["nupp.runtime.wasm"] = memory or {}})(name)
end

function M.services(catalog)
    return instance({["nupp.services"] = true}, {
        ["nupp.runtime.services.artifact"] = catalog or {providers = {}}
    })("nupp.services")
end

function M.family(kind)
    local contract = "nupp.runtime.services." .. kind
    local facade = "nupp." .. kind
    local load = instance({
        ["nupp.services"] = true,
        [contract] = true,
        [facade] = true,
        ["nupp.runtime.provider." .. kind] = true
    })

    return load, load(contract).service
end

return M
