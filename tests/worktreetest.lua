local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local test = require("assert")
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
local ROOT = HERE .. "/.."

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local function temporary()
    local path = os.tmpname()
    os.remove(path)
    assert(os.execute("mkdir -p " .. quote(path)) == 0)
    return path
end

-- A Windows drive-letter path (`C:/...`) and the MSYS spelling Git Bash's own
-- utilities normalize it to (`/c/...`) name the same real location; comparing them
-- literally would fail on a difference in spelling rather than in substance.
local function posixDrive(path)
    return (path:gsub("^([A-Za-z]):/", function(drive)
        return "/" .. drive:lower() .. "/"
    end))
end

function M.helperSeedsOnlyReusableWorktreeState()
    local parent = temporary()
    local origin, task, dirtyTask = parent .. "/origin", parent .. "/task", parent .. "/dirty-task"
    assert(
        os.execute(
            (
                "mkdir -p %s/scripts %s/src %s/build/cache " .. "%s/build/nupp/tools %s/build/lib %s/.rocks"
            ):format(quote(origin), quote(origin), quote(origin), quote(origin), quote(origin), quote(origin))
        ) == 0
    )
    assert(os.execute(("cp %s/scripts/worktree %s/scripts/worktree"):format(quote(ROOT), quote(origin))) == 0)
    assert(os.execute("chmod +x " .. quote(origin .. "/scripts/worktree")) == 0)
    write(origin .. "/src/main.nupp", "return true\n")
    write(origin .. "/build/cache/checks.buf", "compiler-cache\n")
    write(origin .. "/build/.nupp-test-times.json", '{"suites":{"slow":10}}\n')
    write(origin .. "/build/nupp/tools/main.lua", "return true\n")
    write(origin .. "/build/nupp.lua", "return true\n")
    write(origin .. "/build/lib/native", "library\n")
    write(origin .. "/build/.nupp-state.json", "{}\n")
    write(origin .. "/.rocks/sentinel", "rocks\n")
    assert(
        os.execute(
            (
                "git -C %s init -q && git -C %s config user.name Test "
                .. "&& git -C %s config user.email test@example.com && git -C %s add scripts src "
                .. "&& git -C %s commit -q -m initial"
            ):format(quote(origin), quote(origin), quote(origin), quote(origin), quote(origin))
        ) == 0
    )
    write(origin .. "/build/.nupp-complete", "complete\n")

    local command = ("%s/scripts/worktree cached-worktree %s HEAD >/dev/null"):format(quote(origin), quote(task))
    assert(os.execute(command) == 0, "worktree helper failed")
    assert(read(task .. "/.rocks/sentinel") == "rocks\n", "the dependency link did not reach the origin")
    assert(read(task .. "/build/cache/checks.buf") == "compiler-cache\n", "the incremental cache was not seeded")
    assert(read(task .. "/build/.nupp-test-times.json"):find('"slow":10', 1, true), "test timings were not seeded")
    assert(read(task .. "/build/nupp/tools/main.lua") == "return true\n", "a current compiler was not seeded")
    assert(
        os.execute(("test ! %s/src/main.nupp -nt %s/build/.nupp-complete"):format(quote(task), quote(task))) == 0,
        "the copied completion stamp remained older than a fresh checkout"
    )
    -- A current timestamp is not enough when the origin compiler was built from
    -- uncommitted source. Its incremental cache remains safe to seed, but its generated
    -- compiler must not be mistaken for output of the clean revision.
    write(origin .. "/src/main.nupp", "return false\n")
    write(origin .. "/build/.nupp-complete", "complete after dirty build\n")
    command = ("%s/scripts/worktree dirty-worktree %s HEAD >/dev/null"):format(quote(origin), quote(dirtyTask))
    assert(os.execute(command) == 0, "dirty-origin worktree helper failed")
    assert(
        read(dirtyTask .. "/build/cache/checks.buf") == "compiler-cache\n",
        "a dirty origin stopped the safe incremental cache seed"
    )
    local dirtyCompiler = io.open(dirtyTask .. "/build/nupp/tools/main.lua", "rb")
    assert(not dirtyCompiler, "generated compiler output from dirty source was copied into a clean worktree")

    os.execute(("git -C %s worktree remove --force %s >/dev/null 2>&1"):format(quote(origin), quote(task)))
    os.execute(("git -C %s worktree remove --force %s >/dev/null 2>&1"):format(quote(origin), quote(dirtyTask)))
    os.execute("rm -rf " .. quote(parent))
end

-- `.rocks` is ignored, so it belongs to a checkout rather than a revision and a
-- worktree begins without one. The helper links it, but a worktree made any
-- other way does not run the helper, and the suites needing a rock tree then
-- fail as missing modules with nothing saying a setup step was skipped. The
-- launcher links it lazily so that how a worktree was made stops deciding
-- whether its tests can run.
function M.theRockTreeIsLinkedByWhicheverCommandRunsFirst()
    if package.config:sub(1, 1) == "\\" then
        test.skip("linking the rock tree needs a symlink the host may refuse")
    end
    local parent = temporary()
    local origin, task = parent .. "/origin", parent .. "/task"
    assert(os.execute(("mkdir -p %s/.rocks %s/src"):format(quote(origin), quote(origin))) == 0)
    assert(os.execute(("cp %s/scripts/rocks.sh %s/rocks.sh"):format(quote(ROOT), quote(parent))) == 0)
    write(origin .. "/.rocks/sentinel", "rocks\n")
    write(origin .. "/src/main.nupp", "return true\n")
    assert(
        os.execute(
            (
                "git -C %s init -q && git -C %s config user.name Test "
                .. "&& git -C %s config user.email test@example.com && git -C %s add src "
                .. "&& git -C %s commit -q -m initial"
            ):format(quote(origin), quote(origin), quote(origin), quote(origin), quote(origin))
        ) == 0
    )
    -- Deliberately not `scripts/worktree`: this is the bare `git worktree add`
    -- a person or a tool that has never heard of this repository would run.
    assert(os.execute(("git -C %s worktree add -q %s -b task"):format(quote(origin), quote(task))) == 0)
    assert(not io.open(task .. "/.rocks/sentinel", "rb"), "the bare worktree began with a rock tree")

    local link = (". %s/rocks.sh && link_development_rocks %s"):format(quote(parent), quote(task))
    assert(os.execute(link) == 0, "linking the rock tree failed")
    assert(read(task .. "/.rocks/sentinel") == "rocks\n", "the worktree was not linked to the origin tree")

    -- A link rather than a copy, so a rock installed from any worktree is there
    -- for all of them.
    write(origin .. "/.rocks/later", "installed later\n")
    assert(read(task .. "/.rocks/later") == "installed later\n", "the rock tree was copied rather than linked")

    -- Whatever is already there is the answer, including a link left dangling by
    -- a checkout that moved: replacing it silently would lose a state somebody
    -- made deliberately.
    assert(os.execute("rm " .. quote(task .. "/.rocks")) == 0)
    assert(os.execute(("ln -s %s %s"):format(quote(parent .. "/gone"), quote(task .. "/.rocks"))) == 0)
    assert(os.execute(link) == 0, "a dangling rock tree link made the helper fail")
    local dangling = io.popen(("readlink %s"):format(quote(task .. "/.rocks")))
    local target = dangling:read("*l")
    dangling:close()
    assert(posixDrive(target) == posixDrive(parent .. "/gone"), "an existing rock tree link was replaced")

    -- A main checkout without a rock tree has not been provisioned, and the
    -- build that provisions it is the answer there. Linking it to itself, or to
    -- whatever a parent directory happens to hold, would hide that.
    assert(os.execute("rm -rf " .. quote(origin .. "/.rocks")) == 0)
    assert(os.execute((". %s/rocks.sh && link_development_rocks %s"):format(quote(parent), quote(origin))) == 0)
    assert(not io.open(origin .. "/.rocks", "rb"), "an unprovisioned main checkout was given a rock tree")

    os.execute(("git -C %s worktree remove --force %s >/dev/null 2>&1"):format(quote(origin), quote(task)))
    os.execute("rm -rf " .. quote(parent))
end

return M
