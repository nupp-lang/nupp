-- `project.check` under two bundle identities, everything else held constant.
--
-- Diagnostic only, to be removed once the platforms agree.
--
-- `cache.moduleDir` reads its own chunk label. A bundle loaded as `@stage0` has
-- no separator in it, so the label resolves to "." and `toolFingerprint` lists a
-- directory; the same bundle loaded under its real path resolves to something
-- ending in `bootstrap` and takes a branch that lists nothing at all. Two probes
-- differing only in that label therefore run different code, which is what made
-- an earlier reading look decisive when it was not.
--
-- Run twice, once per identity, in a fresh process each time.
local mode, rootArg = ...
if (mode ~= "stage0" and mode ~= "bootstrap")
    or (rootArg ~= "dot" and rootArg ~= "absolute") then
    io.write("usage: diagnose-discovery.lua stage0|bootstrap dot|absolute\n")
    os.exit(2)
end

local root = os.getenv("NUPP_COMPILER_ROOT") or "."
local bundle = root .. "/bootstrap/nupp.lua"

local lines = {}
local function say(...)
    lines[#lines + 1] = table.concat({...}, "\t")
end

say("mode", mode, rootArg)
say("root", root)
say("jit.os", (jit and jit.os) or "?")

-- The same stripped source both times; only the name it is given differs.
local handle = assert(io.open(bundle, "rb"), "cannot read " .. bundle)
local source = handle:read("*a")
handle:close()
local kept = {}
for line in (source .. "\n"):gmatch("([^\n]*)\n") do
    kept[#kept + 1] = line
end
for index = #kept, 1, -1 do
    if kept[index]:find("os%s*%.%s*exit") then
        for drop = #kept, index, -1 do
            kept[drop] = nil
        end
        break
    end
end
local label = mode == "stage0" and "@stage0" or ("@" .. bundle)
say("chunk-label", label)
assert(loadstring(table.concat(kept, "\n"), label))()

-- Installed before anything captures it. `build/cache.nupp` copies
-- `fs.listFiles` into a local as it loads, so a later substitution would leave
-- the original in place.
local fsMod = require("nupp.compiler.fs")
local listings = 0
local realListFiles = fsMod.listFiles
fsMod.listFiles = function(under)
    listings = listings + 1
    say("listFiles", tostring(under))
    return realListFiles(under)
end

local cache = require("nupp.compiler.build.cache")
say("fingerprint", tostring(cache.toolFingerprint and cache.toolFingerprint()))
say("listFiles-after-fingerprint", tostring(listings))

-- `project.check` reports through stderr, so stderr is where the count comes
-- from. A table stands in because a file handle has no writable methods.
local captured = {}
local realStderr = io.stderr
io.stderr = {
    write = function(_, ...)
        captured[#captured + 1] = table.concat({...})
        return true
    end,
}

local project = require("nupp.compiler.build.project")
-- The CLI passes ".", not an absolute path. Which of the two the checker gets
-- is a difference in its own right, so it is varied rather than assumed.
local checkRoot = rootArg == "dot" and "." or root
say("check-root", checkRoot)
local ok, code = pcall(project.check, checkRoot, {})
io.stderr = realStderr

local text = table.concat(captured)
local counts, ordered = {}, {}
for found in text:gmatch("(NUPP%d+)") do
    counts[found] = (counts[found] or 0) + 1
end
for found, n in pairs(counts) do
    ordered[#ordered + 1] = {code = found, n = n}
end
table.sort(ordered, function(a, b) return a.n > b.n end)

say("check-returned", tostring(ok), tostring(code))
say("listFiles-total", tostring(listings))
say("diagnostic-bytes", tostring(#text))
if #ordered == 0 then
    say("diagnostic", "none", "0")
end
for index = 1, math.min(#ordered, 6) do
    say("diagnostic", ordered[index].code, tostring(ordered[index].n))
end
for first in text:gmatch("([^\n]*NUPP%d+[^\n]*)") do
    say("first-diagnostic", first:sub(1, 130))
    break
end

io.write(table.concat(lines, "\n"), "\n")
