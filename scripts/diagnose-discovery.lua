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

-- Deliberately not substituted. The production enumeration does not go through
-- `fs`: it shells to `dir /s /b` on Windows and `find` on Unix, which is the
-- most platform-specific step in the whole path, and answering it from git was
-- masking exactly the part worth exercising. Only the fingerprint's walk above
-- is stood in for, and that one does need the provider.
local envMod = require("nupp.compiler.env")

local incremental = require("nupp.compiler.incremental")

-- The include set a compiler build uses, named rather than inherited, so the
-- order below is the order `buildModules` walks and not whatever the root
-- happens to contain.
local ok, inc = pcall(incremental.new, root, {
    config = {include = {"src", "build/generated"}},
})
if not ok then
    say("incremental.new", "failed", tostring(inc))
    io.write(table.concat(lines, "\n"), "\n")
    return
end

say("manifest-include", table.concat((envMod.new(root).config or {}).include or {}, ","))

local targets = {
    {file = "src/nupp/compiler/cst.nupp", name = "Tname"},
    {file = "src/nupp/compiler/types.nupp", name = "AssociatedReached"},
    {file = "src/nupp/compiler/cli/spec.nupp", name = "Handler"},
}

-- Whether the index still carries each name from its owning module. Asked
-- before and after every check that reports something, because a name that
-- disappears partway names the check that removed it.
local function indexState(label)
    local index = inc.projectIndex()
    local owners = {}
    for name, path in pairs((index and index.modules) or {}) do
        owners[path] = name
    end
    for _, target in ipairs(targets) do
        local owner = owners[root .. "/" .. target.file]
        local found = false
        for _, entry in ipairs(((index and index.byName) or {})[target.name] or {}) do
            if entry.moduleName == owner then found = true end
        end
        say("index", label, target.name, "owner=" .. tostring(owner),
            "present=" .. tostring(found))
    end
end

indexState("initial")

-- The same two steps `buildModules` takes: list the source files, then keep
-- only those `moduleNameForPath` names. It answers nil for a project
-- declaration file, so a build never checks one; a probe that skips this filter
-- checks eleven files the build does not and stops on the first that will not
-- parse as a module.
local ordered = envMod.listSourceFiles(inc.env, false)
local seeded = {}
for _, path in ipairs(ordered) do
    if envMod.moduleNameForPath(inc.env, path) then
        seeded[#seeded + 1] = path
    end
end
say("sourceFiles", tostring(#ordered), "seeded=" .. #seeded)

-- `main` first, the way a build reaches it, then everything else in order.
local first = root .. "/src/nupp/compiler/main.nupp"
local queue = {first}
for _, path in ipairs(seeded) do
    if path ~= first then queue[#queue + 1] = path end
end

local reported = 0
for position, path in ipairs(queue) do
    local checked
    local fine = pcall(function() checked = inc.checkFile(path) end)
    local count = fine and #((checked or {}).diags or {}) or -1
    if count ~= 0 then
        reported = reported + 1
        local relative = (path:gsub("^" .. root:gsub("%p", "%%%0") .. "/", ""))
        say("first-diagnostics", tostring(position), relative, "diags=" .. count)
        for index = 1, math.min(count, 4) do
            local d = checked.diags[index]
            say("diag", relative, tostring(d.code), tostring(d.line),
                tostring(d.msg):sub(1, 100))
        end
        indexState("after:" .. relative)
        if reported >= 2 then break end
    end
end
if reported == 0 then
    say("first-diagnostics", "none", "checked=" .. #queue)
    indexState("final")
end

io.write(table.concat(lines, "\n"), "\n")
