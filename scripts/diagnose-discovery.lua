-- What the project index learns from a source file, on this platform.
--
-- Diagnostic only, to be removed once the platforms agree.
--
-- `envMod.projectHeader` answers an empty declaration list when the parse it is
-- given carries any error, and says nothing about it. A module whose header is
-- empty still resolves and still publishes its values; what it stops publishing
-- is its module-qualified records. That is the boundary the missing
-- `AssociatedReached`, `Handler` and CST records sit on, so this reads the three
-- files, parses them, and records what the header made of them.
--
-- It deliberately does not use `nupp.compiler.fs`: listing a directory needs the
-- native provider, and needing the thing under investigation is what made the
-- previous two probes report nothing on the platform that mattered.
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
        if lines[index]:find("os%s*%.%s*exit") then
            for drop = #lines, index, -1 do
                lines[drop] = nil
            end
            break
        end
    end
    assert(loadstring(table.concat(lines, "\n"), "@stage0"))()
end

loadBundle(root .. "/bootstrap/nupp.lua")

local parser = require("nupp.compiler.parser")
local envMod = require("nupp.compiler.env")

local lines = {}
local function say(...)
    lines[#lines + 1] = table.concat({...}, "\t")
end

say("root", root)
say("separator", package.config:sub(1, 1))
say("jit.os", (jit and jit.os) or "?")

-- Read separately from the probe's own work, so a provider that is missing is
-- reported rather than fatal.
local listing = io.popen and io.popen("ls -l " .. root .. "/build/lib 2>&1")
if listing then
    for line in listing:lines() do say("build/lib", line) end
    listing:close()
end

local env = envMod.new(root)

for _, relative in ipairs({
    "src/nupp/compiler/cst.nupp",
    "src/nupp/compiler/types.nupp",
    "src/nupp/compiler/cli/spec.nupp",
}) do
    local path = root .. "/" .. relative
    local handle = io.open(path, "rb")
    if not handle then
        say("file", relative, "unreadable")
    else
        local source = handle:read("*a")
        handle:close()

        -- Byte-level, because a checkout that converted line endings is the
        -- first thing that would make one platform parse what another cannot.
        local crlf = select(2, source:gsub("\r\n", ""))
        local lf = select(2, source:gsub("\n", ""))
        say("file", relative, "bytes=" .. #source,
            "crlf=" .. crlf, "lf=" .. lf, "cr-only=" .. (select(2, source:gsub("\r", "")) - crlf))

        local parsed = parser.parse(source, path)
        say("parse", relative, "errors=" .. #parsed.errors)
        for index = 1, math.min(#parsed.errors, 3) do
            local e = parsed.errors[index]
            say("parse-error", relative, tostring(e.line) .. ":" .. tostring(e.col),
                tostring(e.msg))
        end

        local header = envMod.projectHeader(env, path, parsed)
        say("header", relative, "module=" .. tostring(header.moduleName),
            "moduleLocal=" .. tostring(header.moduleLocal),
            "declarations=" .. #header.declarations)
        for _, declaration in ipairs(header.declarations) do
            say("decl", relative, declaration.name, tostring(declaration.kind),
                tostring(declaration.visibility))
        end
    end
end

io.write(table.concat(lines, "\n"), "\n")
