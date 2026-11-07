local testAssert = require("assert")
-- The scaffolder: what a TEMPLATE argument means, what substitution does, what
-- the sandbox refuses, and what never reaches the disk.
--
-- The acceptance tests at the bottom are the ones that keep a built-in template
-- from rotting: they scaffold it and then hold the result to `check`, `build`,
-- `test` and `run`, which is the promise `nupp init` makes and the one a reader
-- tests first.
local template = require("nupp.tools.template")

local HERE = require("helpers.paths").absoluteTests
local ROOT = HERE .. "/.."
local NUPP = os.getenv("NUPP_TEST_BIN") or ROOT .. "/bin/nupp"

local function exists(path)
    local file = io.open(path, "rb")
    if not file then
        return false
    end
    file:close()

    return true
end

local function write(path, text)
    os.execute("mkdir -p '" .. path:match("^(.*)/[^/]+$") .. "'")
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function tempDirectory()
    local dir = os.tmpname()
    os.remove(dir)
    return dir
end

local function remove(dir)
    os.execute("rm -rf '" .. dir .. "'")
end

local function shell(command)
    local pipe = assert(io.popen(command .. " 2>&1"))
    local out = pipe:read("*a")
    local ok = pipe:close()
    return ok and true or false, out
end

-- A template on disk, from a table of relative path to contents.
local function templateDirectory(files)
    local dir = tempDirectory()
    for path, text in pairs(files) do
        write(dir .. "/" .. path, text)
    end

    return dir
end

-- One store for every project this suite scaffolds.
--
-- A scaffold's `check`, `build` and `test` are one reuse story, and so are two
-- scaffolds': what a generated project compiles is the compiler's own modules,
-- and a store is keyed by their content rather than by which project asked for
-- them. An empty store per scaffold made each of them pay for that surface
-- again, which on the browser templates -- a rock dependency and a `lua51`
-- target between them -- measured about a fifth of a build.
--
-- Private to this process rather than inherited from the shard: no result here
-- depends on the unrelated temporary projects the runner packed beside it, and
-- no two of this suite's own lanes take turns discarding each other's entries,
-- which is what one store shared between processes would come to.
local SCAFFOLD_STORE = (os.getenv("NUPP_CACHE_DIR") or tempDirectory()) .. "-templates"

-- Resolution ---------------------------------------------------------------

-- Substitution --------------------------------------------------------------

-- The template manifest and its sandbox -------------------------------------

-- Variable values -----------------------------------------------------------

-- Reading a tree ------------------------------------------------------------

-- Refusals before writing ---------------------------------------------------

local function planRefuses(files, label, needle, name)
    local dir = templateDirectory(files)
    local into = tempDirectory()
    local plan, err = template.plan({kind = "directory", path = dir}, into, {name = name})
    testAssert.eq(plan, nil, label)
    assert(err:find(needle, 1, true), err)
    assert(not exists(into), "and the destination was left alone")
    remove(dir)
end

-- The library tables every Lua chunk in this process shares, so a test that lets
-- something near them can put them back whatever happened, and say what moved.
local SHARED = {string = string, table = table, math = math}

local function snapshotShared()
    local saved = {}
    for name, library in pairs(SHARED) do
        saved[name] = {}
        for key, value in pairs(library) do
            saved[name][key] = value
        end
    end

    return saved
end

local function restoreShared(saved)
    local changed = {}
    for name, library in pairs(SHARED) do
        local keys = {}
        for key in pairs(library) do
            keys[#keys + 1] = key
        end
        for key in pairs(saved[name]) do
            keys[#keys + 1] = key
        end
        for _, key in ipairs(keys) do
            if library[key] ~= saved[name][key] then
                changed[#changed + 1] = name .. "." .. key
                library[key] = saved[name][key]
            end
        end
    end
    table.sort(changed)

    return changed
end

-- Plans with the shared libraries at risk: `tamper` runs just before planning,
-- and everything is put back before anything is asserted.
local function planWhileTampered(files, tamper)
    local dir = templateDirectory(files)
    local into = tempDirectory()
    local saved = snapshotShared()
    local ok, plan, err = pcall(function()
        if tamper then
            tamper()
        end
        return template.plan({kind = "directory", path = dir}, into)
    end)
    local changed = restoreShared(saved)
    remove(dir)
    assert(ok, plan)

    return plan, err, into, changed
end

-- The built-in templates ----------------------------------------------------

-- Remote templates ----------------------------------------------------------
--
-- Served over `file://` from a repository made here, so the suite needs no
-- network and still exercises the clone, the commit resolution and the
-- subdirectory.

local function repository(files)
    local dir = templateDirectory(files)
    assert(
        shell(
            "cd '"
            .. dir
            .. "' && git init -q . && git add -A"
            .. " && git -c user.email=t@t -c user.name=t commit -qm fixture"
        )
    )

    return dir, "file://" .. dir
end

-- The step restriction ------------------------------------------------------

-- Acceptance: the scaffolded projects actually work -------------------------

local function scaffoldAndVerify(name, project, expectedOutput, prepare)
    local into = tempDirectory()
    local plan = assert(template.plan(assert(template.resolve(name)), into, {name = project}))
    assert(template.write(plan))
    if prepare then
        prepare(into)
    end

    -- Every command below is about this one scaffold, so each says which
    -- template it scaffolded and where, rather than leaving a failure to be
    -- traced back to a directory the message never named.
    local scaffolded = name .. " scaffolded into " .. into
    local quoted = "cd '" .. into .. "' && NUPP_CACHE_DIR='" .. SCAFFOLD_STORE .. "' NUPP=" .. NUPP .. " "
    local ok, out = shell(quoted .. NUPP .. " check")
    assert(ok, scaffolded .. " does not check:\n" .. out)
    -- A template is what somebody's first project looks like, so it is held to the
    -- one formatted spelling, and warns about nothing.
    assert(not out:find("warning", 1, true), scaffolded .. " checks with warnings:\n" .. out)
    ok, out = shell(quoted .. NUPP .. " fmt --check")
    assert(ok, scaffolded .. " is not formatted:\n" .. out)
    ok, out = shell(quoted .. NUPP .. " build")
    assert(ok, scaffolded .. " does not build:\n" .. out)
    -- A build stages the compiler's runtime sources for a portable target, and the
    -- project's checking must not reach them.
    ok, out = shell(quoted .. NUPP .. " check")
    assert(ok, scaffolded .. " does not check once built:\n" .. out)
    ok, out = shell(quoted .. NUPP .. " test")
    assert(ok, scaffolded .. " does not pass its own tests:\n" .. out)
    if expectedOutput then
        ok, out = shell(quoted .. NUPP .. " run src/main.nupp")
        assert(ok, scaffolded .. " does not run:\n" .. out)
        assert(
            out:find(expectedOutput, 1, true),
            scaffolded .. " ran but printed " .. out .. " rather than " .. expectedOutput
        )
    end
    remove(into)
end

local function withDevelopmentRocks(into)
    local path = into .. "/nupp.lua"
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    local changed, count = text:gsub(
        'kind = "luarocks",',
        'kind = "luarocks",\n         tree = ' .. string.format("%q", ROOT .. "/.rocks") .. ",",
        1
    )
    testAssert.eq(count, 1, "the generated project has one rock dependency")
    write(path, changed)
end

-- A game template's manifest ------------------------------------------------

return {
    testAssert = testAssert,
    template = template,
    HERE = HERE,
    ROOT = ROOT,
    NUPP = NUPP,
    exists = exists,
    write = write,
    tempDirectory = tempDirectory,
    remove = remove,
    shell = shell,
    templateDirectory = templateDirectory,
    SCAFFOLD_STORE = SCAFFOLD_STORE,
    planRefuses = planRefuses,
    SHARED = SHARED,
    snapshotShared = snapshotShared,
    restoreShared = restoreShared,
    planWhileTampered = planWhileTampered,
    repository = repository,
    scaffoldAndVerify = scaffoldAndVerify,
    withDevelopmentRocks = withDevelopmentRocks,
}
