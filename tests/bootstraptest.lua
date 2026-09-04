-- The repository must remain runnable when the ignored build tree is absent.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = HERE .. "/.."

local M = {}

local function readFile(path)
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

-- A fresh checkout renders docs with the tracked compiler before any source has
-- rebuilt it. Keep both halves of an admonition in that bundle: without the
-- container renderer the markers become prose, and without the CSS the aside is
-- structurally correct but visually plain.
function M.trackedBootstrapCarriesAdmonitions()
    local source = readFile(ROOT .. "/bootstrap/nupp.lua")
    assert(source:find("ADMONITION_TITLES", 1, true), "tracked bootstrap lacks the admonition container renderer")
    -- Matched with the brace loose from the selector, because how the bundled
    -- stylesheet is spelled is not what this is about: the CSS was inlined and
    -- minified when it lived in Lua source and is an ordinary stylesheet
    -- resource now that it lives in a .css file.
    assert(source:find("%.nuppdoc%-admonition%s*{"), "tracked bootstrap lacks admonition styling")
end

function M.launcherFallsBackToTrackedBootstrap()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/bin'") == 0)
    assert(os.execute(("cp '%s/bin/nupp' '%s/bin/nupp'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/bootstrap' '%s/bootstrap'"):format(ROOT, dir)) == 0)
    -- The launcher is `bin/nupp` and the scripts it reads. It selects an
    -- interpreter before it runs anything, and provisions the pinned one where the
    -- machine has none, so a tree carrying the bootstrap without them is not a
    -- tree anybody has.
    assert(os.execute(("cp -R '%s/scripts' '%s/scripts'"):format(ROOT, dir)) == 0)

    local p = assert(io.popen(("'%s/bin/nupp' --help 2>&1"):format(dir)))
    local out = p:read("*a")
    p:close()
    assert(out:find("Usage:\n  nupp", 1, true), "launcher did not start the tracked bootstrap compiler: " .. out)

    local commands = {
        "ast",
        "check",
        "fmt",
        "build",
        "clean",
        "tasks",
        "test",
        "doc",
        "fixpoint",
        "run",
        "import-c",
        "rock",
        "lsp",
        "help",
    }
    for _, command in ipairs(commands) do
        p = assert(io.popen(("'%s/bin/nupp' %s --help 2>&1"):format(dir, command)))
        out = p:read("*a")
        p:close()
        assert(out:find("Usage:", 1, true), "tracked bootstrap lacks help for " .. command .. ": " .. out)
    end

    os.execute("rm -rf '" .. dir .. "'")
end

-- A tree carrying the launcher and two compilers that do nothing but say which
-- one they are. What these cases test is the launcher's choice between them and
-- what it waits for on the way, and a real pair would take a build to produce
-- and answer the same question.
--
-- The Rust native provider is planted rather than built for the same reason: the
-- launcher stages one before every command that reads a source, and this tree
-- has no `runtime` to build one from. Planted under all three platform names,
-- because which one is looked for is decided by `uname` and none of them is
-- ever opened.
local function plantedTree()
    local dir = os.tmpname()
    os.remove(dir)
    assert(
        os.execute(
            ("mkdir -p '%s/bin' '%s/bootstrap' '%s/build/nupp/compiler' '%s/build/lib'"):format(dir, dir, dir, dir)
        ) == 0
    )
    assert(os.execute(("cp '%s/bin/nupp' '%s/bin/nupp'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/scripts' '%s/scripts'"):format(ROOT, dir)) == 0)
    local function plant(path, text)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    plant("bootstrap/nupp.lua", 'print("BOOTSTRAP")\n')
    plant("build/nupp/compiler/main.lua", 'print("BUILT")\n')
    for _, name in ipairs({"libnupp_native_v2_dev.dylib", "libnupp_native_v2_dev.so", "nupp_native_v2_dev.dll",}) do
        plant("build/lib/" .. name, "")
    end

    return dir, plant
end

local function ran(dir, command)
    local p = assert(io.popen(("cd '%s' && ./bin/nupp %s 2>&1"):format(dir, command)))
    local out = p:read("*a")
    p:close()
    return out
end

-- Which compiler a command runs is decided on whether one is there, not on
-- whether the completion stamp says the last build finished. Those two differ
-- for the length of every build, because a build removes the stamp before it
-- writes anything -- and a command answering "no compiler here" then runs the
-- bootstrap instead, which is a different compiler with a different digest.
-- Every content key a build writes carries that digest, so a project whose
-- native library one of them linked relinks under the other with nothing
-- changed.
function M.aStamplessTreeStillRunsTheCompilerItHas()
    local dir = plantedTree()

    -- `--help` reads no source, so what it prints is the choice and nothing else.
    assert(
        ran(dir, "--help"):find("BUILT", 1, true),
        "a build in progress has removed the stamp, and the compiler it is rewriting "
        .. "is still a better answer than one from whenever stage zero was refreshed"
    )

    local stamp = assert(io.open(dir .. "/build/.nupp-complete", "wb"))
    stamp:write("complete\n")
    stamp:close()
    assert(ran(dir, "--help"):find("BUILT", 1, true), "and is the answer once the stamp is back")

    assert(os.remove(dir .. "/build/nupp/compiler/main.lua"))
    assert(
        ran(dir, "--help"):find("BOOTSTRAP", 1, true),
        "the bootstrap is for a tree that has no compiler, not for one mid-build"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

-- A build of a tree is one writer of it however it was asked for, so it waits
-- for whoever is already writing. `nupp build --target dist` used to be outside
-- the lock entirely: it removed the completion stamp for the minute it ran, and
-- every other command in the tree read that as a tree nobody had built and
-- started its own build over the same output directory.
function M.aBuildWaitsForTheBuildAlreadyRunning()
    local dir = plantedTree()

    -- Held by something that is alive, since a lock whose holder is gone is one
    -- a killed build left behind and is taken rather than waited for.
    local script = (
        [[
      cd '%s' && mkdir -p build/.nupp-build-lock
      sleep 4 & printf '%%s\n' "$!" > build/.nupp-build-lock/pid
      ./bin/nupp build > ran.txt 2>&1 &
      sleep 2
      printf 'while held: [%%s]\n' "$(cat ran.txt)"
      wait
      printf 'after: [%%s]\n' "$(cat ran.txt)"
   ]]
    ):format(dir)
    local p = assert(io.popen(script .. " 2>&1"))
    local out = p:read("*a")
    p:close()

    assert(out:find("while held: []", 1, true), "a build ran while another held the lock: " .. out)
    assert(out:find("after: [BUILT]", 1, true), "and did not run once the lock was free: " .. out)

    os.execute("rm -rf '" .. dir .. "'")
end

-- Help output proves only that the tracked Lua loads. The bootstrap also has to
-- understand every language and resolver change used by the current compiler, or a
-- fresh checkout cannot produce its first build.
function M.trackedBootstrapBuildsCurrentCompiler()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    assert(os.execute(("cp '%s/nupp.lua' '%s/nupp.lua'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/src' '%s/src'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/bootstrap' '%s/bootstrap'"):format(ROOT, dir)) == 0)

    local p = assert(io.popen(("cd '%s' && luajit bootstrap/nupp.lua build 2>&1"):format(dir)))
    local out = p:read("*a")
    local ok = p:close()
    assert(ok, "tracked bootstrap cannot build the current compiler: " .. out)

    local stamp = io.open(dir .. "/build/.nupp-complete", "rb")
    assert(stamp, "tracked bootstrap reported success without completing the build: " .. out)
    stamp:close()

    -- A bootstrap is more than an escape hatch for building the current sources:
    -- its generated declarations and lowering passes are the compiler surface a
    -- clean checkout starts from. Make the tracked bytes stale without changing
    -- their behavior and require the ordinary fixpoint to notice.
    local bootstrap = assert(io.open(dir .. "/bootstrap/nupp.lua", "ab"))
    bootstrap:write("\n-- deliberately stale\n")
    bootstrap:close()
    p = assert(io.popen(("cd '%s' && luajit bootstrap/nupp.lua fixpoint 2>&1; echo '__status__:'$?"):format(dir)))
    out = p:read("*a")
    p:close()
    local status = tonumber(out:match("__status__:(%d+)%s*$"))
    assert(status and status ~= 0, "fixpoint accepted a stale tracked bootstrap: " .. out)
    assert(
        out:find("tracked bootstrap is stale", 1, true),
        "fixpoint did not explain how to refresh the stale bootstrap: " .. out
    )
    os.execute("rm -rf '" .. dir .. "'")
end

return M
