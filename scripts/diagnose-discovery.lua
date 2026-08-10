-- What the incremental path makes of this project, on this platform.
--
-- Diagnostic only, to be removed once the platforms agree.
--
-- Parsing and header extraction are ruled out: all three platforms produce the
-- same declarations from the same files, CRLF included. What has not been
-- exercised is the path a build actually takes, which stores each header under a
-- key, assembles them into a project index, and consults that index while
-- checking. This walks that path and reports at each stage, so a header that is
-- stored wrong, an index that loses it, and an index that is correct but not
-- consulted are three different readings rather than one symptom.
--
-- `git ls-files` supplies the file list so `nupp.compiler.fs` stays out of it:
-- listing a directory needs the native provider, and the provider is itself
-- unresolved on the failing platform.
local root = os.getenv("NUPP_COMPILER_ROOT") or "."

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

local lines = {}
local function say(...)
    lines[#lines + 1] = table.concat({...}, "\t")
end

say("root", root)
say("separator", package.config:sub(1, 1))
say("jit.os", (jit and jit.os) or "?")

-- Quoting is the caller's job, and it differs: a single-quoted pathspec is
-- unquoted by a POSIX shell and taken literally by `cmd.exe`, where it then
-- matches nothing. An earlier version of this probe passed one, harvested an
-- empty file list on Windows alone, and reproduced the very symptom it was
-- investigating out of thin air.
--
-- The result is checked rather than the exit status, because this interpreter's
-- `popen` close answers `true` whatever the command did. A sentinel says the
-- command ran; a non-empty list says it found something. A probe that cannot
-- tell "no files" from "no answer" is worse than none.
local function gitFiles(pattern)
    local command = 'git -C "' .. root .. '" ls-files'
    if pattern then
        command = command .. ' "' .. pattern .. '"'
    end
    local listing = assert(io.popen(command .. " 2>&1 && echo __GIT_OK__"))
    local out, ran = {}, false
    for line in listing:lines() do
        if line == "__GIT_OK__" then
            ran = true
        elseif line ~= "" then
            out[#out + 1] = root .. "/" .. line
        end
    end
    listing:close()
    assert(ran, "git ls-files did not run: " .. command .. "\n" .. table.concat(out, "\n"))
    assert(#out > 0, "git ls-files matched nothing: " .. command)
    table.sort(out)
    return out
end

-- The project's own files, and everything tracked for the one other caller that
-- walks the tree: the header store is keyed on a toolchain fingerprint, and that
-- fingerprint lists the compiler's own sources. Untracked files fall outside the
-- fingerprint, which changes the key but not what is stored under it.
local tracked = gitFiles("src/*.nupp")
local everything = gitFiles(nil)
say("tracked-count", tostring(#tracked))
say("tracked-first", tostring(tracked[1]))
say("tracked-total", tostring(#everything))

-- Substituted before anything captures them. `build/cache.nupp` copies
-- `fs.listFiles` into a local when it loads, so patching after requiring the
-- incremental path would leave the original in place and take the probe back
-- through the provider it is meant to avoid.
local fsMod = require("nupp.compiler.fs")
fsMod.listFiles = function(under)
    local prefix, out = under .. "/", {}
    for _, path in ipairs(everything) do
        if path:sub(1, #prefix) == prefix then out[#out + 1] = path end
    end
    return out
end

local envMod = require("nupp.compiler.env")
envMod.listProjectFiles = function()
    return tracked
end

local incremental = require("nupp.compiler.incremental")
local ok, inc = pcall(incremental.new, root)
if not ok then
    say("incremental.new", "failed", tostring(inc))
    io.write(table.concat(lines, "\n"), "\n")
    return
end

say("projectFiles", tostring(#inc.projectFiles()))

local targets = {
    ["src/nupp/compiler/cst.nupp"] = "Tname",
    ["src/nupp/compiler/types.nupp"] = "AssociatedReached",
    ["src/nupp/compiler/cli/spec.nupp"] = "Handler",
}

-- Stage one: what the store hands back for each file, through the query graph
-- rather than by calling projectHeader directly.
for relative in pairs(targets) do
    local path = root .. "/" .. relative
    local header = inc.projectHeader(path)
    if not header then
        say("header", relative, "nil")
    else
        say("header", relative, "module=" .. tostring(header.moduleName),
            "declarations=" .. #(header.declarations or {}))
    end
end

-- Stage two: whether the assembled index carries the names that go missing.
local index = inc.projectIndex()
say("index", "modules=" .. tostring(index and index.modules and (function()
    local n = 0
    for _ in pairs(index.modules) do n = n + 1 end
    return n
end)() or "?"))
-- `byName` is keyed on the bare declaration name and holds every module that
-- declares it, so the question is whether the owning module is among them.
for relative, wanted in pairs(targets) do
    local owner
    for name, path in pairs((index and index.modules) or {}) do
        if path:sub(-#relative) == relative then owner = name end
    end
    local entries = ((index and index.byName) or {})[wanted]
    local found = false
    for _, entry in ipairs(entries or {}) do
        if entry.moduleName == owner then found = true end
    end
    say("index-name", wanted, "owner=" .. tostring(owner),
        "entries=" .. #(entries or {}), "from-owner=" .. tostring(found))
end

-- Stage three: what checking actually reports for the files that failed.
for _, relative in ipairs({
    "src/nupp/compiler/parser.nupp",
    "src/nupp/compiler/associated.nupp",
    "src/nupp/compiler/cli/check.nupp",
}) do
    local path = root .. "/" .. relative
    local checked = pcall(inc.checkFile, path) and inc.checkFile(path) or nil
    if not checked then
        say("check", relative, "raised")
    else
        local count = #(checked.diags or {})
        say("check", relative, "diags=" .. count)
        for index2 = 1, math.min(count, 3) do
            local d = checked.diags[index2]
            say("check-diag", relative, tostring(d.code), tostring(d.line),
                tostring(d.msg):sub(1, 110))
        end
    end
end

io.write(table.concat(lines, "\n"), "\n")
