local test = require("assert")
local process = require("nupp.compiler.build.process")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not here:match("^/") then
    local pipe = assert(io.popen("pwd"))
    here = pipe:read("*l") .. "/" .. here
    pipe:close()
end
local compiler = here .. "/../bin/nupp"
local M = {}

local function quote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

function M.buildsFileReadersAndLineIteratorsInAColdComponent()
    local directory = os.tmpname()
    if package.config:sub(1, 1) == "\\" then
        directory = directory:gsub("^/([A-Za-z])/", "%1:/")
    end
    os.remove(directory)
    assert(os.execute("mkdir -p " .. quote(directory .. "/src")) == 0)
    write(
        directory .. "/nupp.lua",
        [[
return {include = {"src"}, build = {kind = "component", outDir = "build",
    entries = {"fixture"}, exports = {"fixture.read"}}}
]]
    )
    write(
        directory .. "/src/fixture.nupp",
        [[
module fixture
local files = require("nupp.io.files")
export function read(path: string): string
    local iterator = assert(files.lines(path))
    local text = ""
    for line in iterator do
        collectgarbage("collect")
        text = text .. assert(line) .. "\n"
    end
    return text
end
]]
    )
    -- A preceding check can warm declarations and hide incorrect ownership
    -- contracts when the component checks its carried standard modules.
    local status, output = process.capture({compiler, "build"}, {
        cwd = directory,
        env = {NUPP_CACHE_DIR = directory .. "/cache"},
    })
    local artifact = io.open(directory .. "/build/component.nuppc", "rb")
    local bytes = artifact and artifact:read("*a") or ""
    if artifact then
        artifact:close()
    end
    write(directory .. "/lines.txt", string.rep("x", 70000) .. "\r\n\nlast")
    write(
        directory .. "/read.nupp",
        [[
local fixture = require("fixture")
assert(fixture.read("lines.txt") == string.rep("x", 70000) .. "\n\nlast\n")
]]
    )
    local ran, runOutput = process.capture({compiler, "run", "read.nupp"}, {cwd = directory})
    os.execute("rm -rf " .. quote(directory))
    test.equal(status, 0, output)
    test.equal(ran, 0, runOutput)
    assert(
        bytes:find('package.preload["nupp.io.files"]', 1, true),
        "the component carries the file implementation it checked"
    )
end

return M
