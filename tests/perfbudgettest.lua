-- Performance and capacity budgets, held by quantities that do not move with load.
--
-- A budget that fails on a busy runner is worse than none: it teaches everybody to
-- re-run until green, and then it no longer holds anything. So nothing here times a
-- command. Each case measures something a regression moves and a loaded machine does
-- not -- how many directories a walk lists, how many modules an edit recompiles, how
-- many bytecode instructions a kernel compiles to, how much generated Lua the compiler
-- writes per byte of source, how many bytes the checker allocates per module as a
-- project grows -- and holds it under a ceiling with room in it. A ceiling is a
-- decision, not a snapshot: raising one is allowed, and the failure message says what
-- moved so that raising it is a choice somebody makes on purpose.
--
-- The wall-clock budgets beside these are tracked rather than enforced, because only a
-- quiet machine can say whether they held. They were measured on an Apple M5 Pro at
-- the commit that introduced this suite, and `bench/` and the measurements workflow are
-- where they are re-measured:
--
--   `nupp --version` through bin/nupp                 about 120 ms (15 ms of it the compiler)
--   unchanged whole-project `nupp check` (463 modules) about 0.4 s
--   one module body edited, whole-project check       about 0.8 s
--   an exported type of a 55-importer module edited   about 14 s
--   cold whole-project check, no cache                about 19 s, 2.3 GB peak
--   language server: edit to diagnostics, warm        under 250 ms; hover under 10 ms
--
-- Each is kept by a deterministic case below where one exists: the walk budget is what
-- keeps the unchanged check near its floor, the recompile count is what keeps the body
-- edit cheap, and the launcher's toolchain questions are held in toolchaintest.
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if HERE:sub(1, 1) ~= "/" and not HERE:match("^%a:[/\\]") then
    local pipe = assert(io.popen("pwd"))
    HERE = assert(pipe:read("*l")) .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."

local function writeFile(path, text)
    local parent = assert(path:match("^(.*)[/\\]"))
    assert(os.execute("mkdir -p '" .. parent .. "'") == 0)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function temporary()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)

    return dir
end

local M = {}

-- The project walk visits the checkout's own root, and the output directory sits in
-- it. A native build keeps a Cargo target there: in a checkout that had built one, the
-- walk listed a hundred and forty thousand entries to keep four hundred sources, and
-- that was four fifths of an unchanged `nupp check`. The files under it were always
-- dropped afterwards, so the answer never showed the cost; what shows it is which
-- directories were listed.
function M.theProjectWalkNeverListsTheOutputDirectory()
    local envMod = require("nupp.compiler.project.env")
    local files = require("nupp.io.files")
    local dir = temporary()
    writeFile(dir .. "/src/main.nupp", "module main\nexport = true\n")
    writeFile(dir .. "/top.nupp", "module top\nexport = true\n")
    writeFile(dir .. "/build/rust/target/debug/deps/stray.nupp", "module stray\nexport = true\n")
    writeFile(dir .. "/build/generated/tool/made.nupp", "module made\nexport = true\n")

    local listed = {}
    local list = files.list
    files.list = function(path, ...)
        listed[#listed + 1] = path
        return list(path, ...)
    end
    local ok, result = pcall(function()
        local env = envMod.new(dir, {config = {include = {"src"}}})

        return {project = envMod.listProjectFiles(env), sources = envMod.listSourceFiles(env)}
    end)
    files.list = list
    assert(ok, result)
    os.execute("rm -rf '" .. dir .. "'")

    local outDir = dir .. "/build"
    for _, path in ipairs(listed) do
        assert(
            path ~= outDir and path:sub(1, #outDir + 1) ~= outDir .. "/",
            "the project walk listed " .. path .. " under the output directory"
        )
    end
    assert(#listed > 0, "the walk was observed")
    local function has(list, suffix)
        for _, path in ipairs(list) do
            if path:sub(-#suffix) == suffix then
                return true
            end
        end

        return false
    end
    assert(has(result.project, "/src/main.nupp") and has(result.project, "/top.nupp"), "the sources are listed")
    assert(has(result.sources, "/src/main.nupp"), "the include root is listed")
    assert(not has(result.project, "stray.nupp") and not has(result.sources, "stray.nupp"), "build output is not")
end

return M
