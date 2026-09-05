-- `nupp run` must derive an entry file's module identity from the project,
-- independently of how the command line spells its path.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local process = assert(io.popen("pwd"))
    HERE = process:read("*l") .. "/" .. HERE
    process:close()
end
local NUPP = HERE .. "/../bin/nupp"

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. string.format("%q", dir)) == 0)
    for name, source in pairs(files) do
        local sub = name:match("^(.*)/[^/]+$")
        if sub then
            assert(os.execute("mkdir -p " .. string.format("%q", dir .. "/" .. sub)) == 0)
        end
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(source)
        file:close()
    end

    return dir
end

local function capture(command)
    local process = assert(io.popen(command .. " 2>&1"))
    local output = process:read("*a")
    process:close()

    return output
end

local M = {}

function M.runKeepsEntryModuleIdentityForAnAbsolutePath()
    local dir = tempProject({
        ["nupp.lua"] = 'return {include = {"src"}}\n',
        ["src/example/main.nupp"] = [[
local value = require("example.internal.value")
print(value)
]],
        ["src/example/internal/value.nupp"] = 'return "inside"\n',
    })
    local relative = capture(("cd %q && %q run src/example/main.nupp"):format(dir, NUPP))
    assert(relative == "inside\n", "the package may import its internal module: " .. relative)
    local absolute = capture(("cd %q && %q run %q"):format(dir, NUPP, dir .. "/src/example/main.nupp"))
    assert(absolute == "inside\n", "an absolute entry path keeps the same package identity: " .. absolute)
    os.execute("rm -rf " .. string.format("%q", dir))
end

return M
