-- The native core's string handlers, differentially: each fixture under
-- tests/fixtures/native/strings checks its answers against literals and prints
-- them, and runs once on the selected core runtime and once on a freshly
-- linked runtime (`scripts/vm-cli runtime --link`). Both execute the Nupp
-- handlers, and their outputs must agree. Slow: it builds the glue and links
-- the runtime.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local FIXTURES = "tests/fixtures/native/strings"

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(("cd %s && %s 2>&1; echo __exit__:$?"):format(quote(ROOT), command)))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

-- The installed compiler image, which the linked runtime runs as the plain one does.
local function installedImage()
    local selected = os.getenv("NUPP_VM_CLI_IMAGE")
    if selected then
        return selected
    end
    local generation = read(ROOT .. "/.nupp/vm-cli/current"):gsub("%s+$", "")

    return ROOT .. "/.nupp/vm-cli/" .. generation .. "/compiler.image"
end

local linked = nil

local function linkedRuntime()
    if not linked then
        local status, output = capture("python3 scripts/vm-cli runtime --link")
        assert(status == 0, "scripts/vm-cli runtime --link failed: " .. output:sub(-6000))
        linked = assert(output:match("([^\r\n]+)%s*$"), "vm-cli runtime named no runtime")
    end

    return linked
end

local function fixtures()
    local names = {}
    local pipe = assert(io.popen(("cd %s && ls %s"):format(quote(ROOT), quote(FIXTURES))))
    for line in pipe:lines() do
        local name = line:match("^(.+)%.nupp$")
        if name then
            names[#names + 1] = name
        end
    end
    pipe:close()
    assert(#names > 0, "no string fixtures")

    return names
end

-- Runs a fixture on the installed runtime and on the linked one (with
-- `environment` beside the selection) and answers the common output.
local function differential(name, environment)
    local path = FIXTURES .. "/" .. name .. ".nupp"
    local status, plain = capture("./bin/nupp run " .. quote(path))
    assert(status == 0, name .. " failed on the installed runtime: " .. plain:sub(-4000))
    local selection = (
        "NUPP_VM_CLI_IMAGE=%s NUPP_VM_BINARY=%s %s"
    ):format(quote(installedImage()), quote(linkedRuntime()), environment or "")
    local native
    status, native = capture(selection .. " ./bin/nupp run " .. quote(path))
    assert(status == 0, name .. " failed on the native core: " .. native:sub(-4000))
    assert(plain == native, name .. " answers differently on the native core:\n" .. native:sub(-4000))
    assert(plain:find("\n", 1, true), name .. " printed nothing")

    return plain
end

function M.stringFixturesAnswerTheSameOnTheNativeCore()
    for _, name in ipairs(fixtures()) do
        differential(name)
    end
end

-- Interleaved collection with the oracle at every cycle: the allocation a
-- concatenation makes is a safepoint under the published frame, and a short
-- result interned after it must find or become the one live string.
function M.stringFixturesSurviveInterleavedCollection()
    differential("concat", "GC_INTERLEAVE=1 GC_ORACLE=1")
end

return M
