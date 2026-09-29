-- Inspect the exact bundled compiler without changing the timed browser host.
-- Usage: lua imported-scope.lua COMPILER.lua SOURCE.nupp
local bundle, sourcePath = ...
assert(loadfile(bundle))()
local json = require("nupp.runtime.provider.lunajson")
local browser = require("nupp.tools.browser").new()
local input = assert(io.open(sourcePath, "rb"))
local source = input:read("*a")
input:close()
local environment = browser:environment()
local before = json.asArray({})
for name, value in pairs(environment.bundled) do
    if type(value) == "table" then
        before[#before + 1] = name
    end
end
table.sort(before)
local response = browser:check(source, "imported-scoreboard.nupp", {strict = true})
local modules = json.asArray({})
for name, value in pairs(environment.bundled) do
    if type(value) == "table" then
        modules[
            #modules + 1
        ] = {
            name = name,
            resource = value.resource,
            sourceBytes = value.source and #value.source or 0,
            declarationOnly = value.declarationOnly == true,
        }
    end
end
table.sort(modules, function(a, b)
    return a.name < b.name
end)
print(json.encode({response = response, beforeModules = before, modules = modules}))
