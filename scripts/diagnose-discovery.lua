-- What the compiler discovers and what it calls each thing.
--
-- Diagnostic only, to be removed once the platforms agree. It exists to compare
-- one platform's answer against another's, and it writes rather than asserts:
-- the comparison is the point, not a verdict.
--
-- The modules come from the tracked stage-0 bundle rather than from `build/`,
-- because the thing being diagnosed is a build that does not finish. A probe
-- that needs the build it is investigating reports nothing on the platform that
-- matters, which is what the first version of this did.
local root = os.getenv("NUPP_COMPILER_ROOT") or "."

-- The bundle registers every compiler module in `package.preload` and then
-- execs the command-line interface on its last line. Everything above that line
-- is the module source; the line itself would take the process with it.
local function loadBundle(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local source = handle:read("*a")
    handle:close()
    local lines = {}
    for line in (source .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    for index = #lines, 1, -1 do
        local line = lines[index]
        if line:find("os%s*%.%s*exit") then
            for drop = #lines, index, -1 do
                lines[drop] = nil
            end
            break
        end
    end
    assert(loadstring(table.concat(lines, "\n"), "@stage0"))()
end

loadBundle(root .. "/bootstrap/nupp.lua")

local fs = require("nupp.compiler.fs")
local envMod = require("nupp.compiler.env")

local lines = {}
local function say(...)
    lines[#lines + 1] = table.concat({...}, "\t")
end

say("root", root)
say("separator", package.config:sub(1, 1))
say("jit.os", (jit and jit.os) or "?")

local files = fs.listFiles(root .. "/src")
say("listFiles-count", tostring(#files))

-- Whether each file the failures name was discovered, and what module name it
-- was given. A missing name is how a file stops contributing its exports
-- without anything failing loudly.
local env = envMod.new(root)
local present = {}
for _, file in ipairs(files) do present[file] = true end
for _, relative in ipairs({
    "src/nupp/compiler/cst.nupp",
    "src/nupp/compiler/types.nupp",
    "src/nupp/compiler/cli/spec.nupp",
}) do
    local full = root .. "/" .. relative
    local named = envMod.moduleNameForPath and envMod.moduleNameForPath(env, full)
    say("target", relative, "discovered=" .. tostring(present[full] or false),
        "module=" .. tostring(named))
end

-- The whole list, relative, so two platforms diff rather than being eyeballed.
local prefix = "^" .. root:gsub("%p", "%%%0")
for _, file in ipairs(files) do
    say("file", (file:gsub(prefix, "")))
end

io.write(table.concat(lines, "\n"), "\n")
