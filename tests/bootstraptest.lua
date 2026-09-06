-- The repository must remain runnable when the ignored build tree is absent.
--
-- What it starts from then is the stage-zero compiler `scripts/toolchain stage0`
-- fetches and verifies against the digest pinned in `scripts/toolchain.pins`. It
-- is not in the tree, so these cases ask the toolchain for it rather than reading
-- a file, and they say so when a machine has never fetched one.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = HERE .. "/.."

local M = {}

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local source = file:read("*a")
    file:close()

    return source
end

local function capture(command)
    local p = assert(io.popen(command))
    local out = p:read("*a")
    local ok = p:close()
    return out, ok
end

-- Cached after the first ask, because every case here wants the same one and the
-- toolchain digests twelve megabytes to answer.
local stage0Path, stage0Asked
local function stage0()
    if not stage0Asked then
        stage0Asked = true
        local out, ok = capture(("'%s/scripts/toolchain' stage0 2>/dev/null"):format(ROOT))
        stage0Path = ok and out:match("([^\n]+)%s*$") or nil
    end

    return stage0Path
end

-- A fresh checkout renders docs with the stage-zero compiler before any source has
-- rebuilt it. Keep both halves of an admonition in that bundle: without the
-- container renderer the markers become prose, and without the CSS the aside is
-- structurally correct but visually plain.
function M.stage0CarriesAdmonitions()
    local path = stage0()
    assert(path, "no stage-zero compiler; run scripts/toolchain stage0")
    local source = assert(readFile(path), "the fetched stage zero is readable")
    assert(source:find("ADMONITION_TITLES", 1, true), "the stage zero lacks the admonition container renderer")
    -- Matched with the brace loose from the selector, because how the bundled
    -- stylesheet is spelled is not what this is about: the CSS was inlined and
    -- minified when it lived in Lua source and is an ordinary stylesheet
    -- resource now that it lives in a .css file.
    assert(source:find("%.nuppdoc%-admonition%s*{"), "the stage zero lacks admonition styling")
end

-- The digest is what authenticates the bundle, so it is the one thing about the
-- bootstrap that is committed. A pin whose digest does not describe the file the
-- toolchain installed means one of them moved without the other.
function M.thePinnedDigestDescribesTheFetchedCompiler()
    local pins = assert(readFile(ROOT .. "/scripts/toolchain.pins"))
    local pinned = pins:match("\nSTAGE0_SHA256=(%x+)")
    assert(pinned and #pinned == 64, "scripts/toolchain.pins carries no stage-zero digest")
    assert(pins:match("\nSTAGE0_TAG=(%S+)"), "scripts/toolchain.pins names no stage-zero release")

    local path = stage0()
    assert(path, "no stage-zero compiler; run scripts/toolchain stage0")
    local found = capture(("shasum -a 256 '%s' 2>/dev/null || sha256sum '%s'"):format(path, path))
    assert(found:match("^(%x+)") == pinned, "the installed stage zero does not have the pinned digest: " .. found)
end

-- A tree with the launcher, the scripts it reads, and no compiler at all still
-- answers, because the launcher can go and get one. That is the whole of what a
-- fresh checkout has.
function M.launcherFallsBackToTheFetchedStageZero()
    assert(stage0(), "no stage-zero compiler; run scripts/toolchain stage0")
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/bin'") == 0)
    assert(os.execute(("cp '%s/bin/nupp' '%s/bin/nupp'"):format(ROOT, dir)) == 0)
    -- The launcher is `bin/nupp` and the scripts it reads. It selects an
    -- interpreter before it runs anything, provisions the pinned one where the
    -- machine has none, and now fetches the compiler through the same script, so a
    -- tree carrying one without the others is not a tree anybody has.
    assert(os.execute(("cp -R '%s/scripts' '%s/scripts'"):format(ROOT, dir)) == 0)

    -- This checkout's toolchain cache, named outright because the copied tree has
    -- no git directory to work it out from. Without it the case reaches the
    -- network for a bundle that is already on the machine.
    local cache = capture(("'%s/scripts/toolchain' --prefix"):format(ROOT))
    cache = assert(cache:match("^%s*(.-)/[^/]+%s*$"), "the toolchain named no prefix")

    local out = capture(("NUPP_TOOLCHAIN_DIR='%s' '%s/bin/nupp' --help 2>&1"):format(cache, dir))
    assert(out:find("Usage:\n  nupp", 1, true), "launcher did not start the stage-zero compiler: " .. out)

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
--
-- The stage zero is planted too, through the toolchain's own source directory: a
-- file with the pinned digest is the one thing that makes `scripts/toolchain
-- stage0` answer offline, and what these cases want is a compiler that prints a
-- word, not the real one.
local function plantedTree()
    local dir = os.tmpname()
    os.remove(dir)
    assert(
        os.execute(
            ("mkdir -p '%s/bin' '%s/build/nupp/compiler' '%s/build/lib' '%s/toolchain'"):format(dir, dir, dir, dir)
        ) == 0
    )
    assert(os.execute(("cp '%s/bin/nupp' '%s/bin/nupp'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/scripts' '%s/scripts'"):format(ROOT, dir)) == 0)
    local function plant(path, text)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    plant("build/nupp/compiler/main.lua", 'print("BUILT")\n')
    for _, name in ipairs({"libnupp_native_v2_dev.dylib", "libnupp_native_v2_dev.so", "nupp_native_v2_dev.dll",}) do
        plant("build/lib/" .. name, "")
    end

    -- One planted stage zero, pinned to its own digest, cached where this tree's
    -- toolchain will look and nowhere a real checkout can see.
    local pins = assert(readFile(dir .. "/scripts/toolchain.pins"))
    plant("stage0.lua", 'print("BOOTSTRAP")\n')
    local digest = capture(("shasum -a 256 '%s/stage0.lua' 2>/dev/null || sha256sum '%s/stage0.lua'"):format(dir, dir))
        :match("^(%x+)")
    local tag = pins:match("\nSTAGE0_TAG=(%S+)")
    assert(os.execute(("mkdir -p '%s/supplied'"):format(dir)) == 0)
    assert(os.execute(("gzip -c '%s/stage0.lua' > '%s/supplied/nupp-stage0-%s.lua.gz'"):format(dir, dir, tag)) == 0)
    plant("scripts/toolchain.pins", (pins:gsub("\nSTAGE0_SHA256=%x+", "\nSTAGE0_SHA256=" .. digest)))

    local env = (
        "NUPP_TOOLCHAIN_DIR='%s/toolchain' NUPP_HOST_OFFLINE=1 NUPP_HOST_SOURCE_DIR='%s/supplied'"
    ):format(dir, dir)

    return dir, plant, env
end

local function ran(dir, env, command)
    local out = capture(("cd '%s' && %s ./bin/nupp %s 2>&1"):format(dir, env, command))
    return out
end

-- Which compiler a command runs is decided on whether one is there, not on
-- whether the completion stamp says the last build finished. Those two differ
-- for the length of every build, because a build removes the stamp before it
-- writes anything -- and a command answering "no compiler here" then runs the
-- stage zero instead, which is a different compiler with a different digest.
-- Every content key a build writes carries that digest, so a project whose
-- native library one of them linked relinks under the other with nothing
-- changed.
function M.aStamplessTreeStillRunsTheCompilerItHas()
    local dir, _, env = plantedTree()

    -- `--help` reads no source, so what it prints is the choice and nothing else.
    assert(
        ran(dir, env, "--help"):find("BUILT", 1, true),
        "a build in progress has removed the stamp, and the compiler it is rewriting "
        .. "is still a better answer than one from whenever stage zero was published"
    )

    local stamp = assert(io.open(dir .. "/build/.nupp-complete", "wb"))
    stamp:write("complete\n")
    stamp:close()
    assert(ran(dir, env, "--help"):find("BUILT", 1, true), "and is the answer once the stamp is back")

    assert(os.remove(dir .. "/build/nupp/compiler/main.lua"))
    assert(
        ran(dir, env, "--help"):find("BOOTSTRAP", 1, true),
        "the stage zero is for a tree that has no compiler, not for one mid-build"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

-- A build of a tree is one writer of it however it was asked for, so it waits
-- for whoever is already writing. `nupp build --target dist` used to be outside
-- the lock entirely: it removed the completion stamp for the minute it ran, and
-- every other command in the tree read that as a tree nobody had built and
-- started its own build over the same output directory.
function M.aBuildWaitsForTheBuildAlreadyRunning()
    local dir, _, env = plantedTree()

    -- Held by something that is alive, since a lock whose holder is gone is one
    -- a killed build left behind and is taken rather than waited for.
    local script = (
        [[
      cd '%s' && mkdir -p build/.nupp-build-lock
      sleep 4 & printf '%%s\n' "$!" > build/.nupp-build-lock/pid
      %s ./bin/nupp build > ran.txt 2>&1 &
      sleep 2
      printf 'while held: [%%s]\n' "$(cat ran.txt)"
      wait
      printf 'after: [%%s]\n' "$(cat ran.txt)"
   ]]
    ):format(dir, env)
    local out = capture(script .. " 2>&1")

    assert(out:find("while held: []", 1, true), "a build ran while another held the lock: " .. out)
    assert(out:find("after: [BUILT]", 1, true), "and did not run once the lock was free: " .. out)

    os.execute("rm -rf '" .. dir .. "'")
end

-- Help output proves only that the fetched Lua loads. The stage zero also has to
-- understand every language and resolver change used by the current compiler, or a
-- fresh checkout cannot produce its first build. That is the rule the pinned
-- release imposes on these sources, and this is what enforces it.
function M.theStageZeroBuildsTheCurrentCompiler()
    local path = stage0()
    assert(path, "no stage-zero compiler; run scripts/toolchain stage0")
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    assert(os.execute(("cp '%s/nupp.lua' '%s/nupp.lua'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/src' '%s/src'"):format(ROOT, dir)) == 0)

    local out, ok = capture(("cd '%s' && luajit '%s' build 2>&1"):format(dir, path))
    assert(ok, "the pinned stage zero cannot build the current compiler: " .. out)

    local stamp = io.open(dir .. "/build/.nupp-complete", "rb")
    assert(stamp, "the stage zero reported success without completing the build: " .. out)
    stamp:close()
    os.execute("rm -rf '" .. dir .. "'")
end

-- Every resource the stage-zero bundle carries is embedded verbatim, so a
-- checkout that translates line endings composes a bundle whose bytes cannot
-- match the released ones -- and the pinned digest is meant to be reproducible
-- from the tag by anyone who rebuilds it. Windows is where that happens.
-- `.gitattributes` has to name every embedded resource, so this asks git the
-- same question the checkout will.
function M.embeddedResourcesHaveOneCheckoutSpelling()
    local manifest = assert(loadfile(ROOT .. "/nupp.lua"))()
    local resources = manifest.build.targets.bootstrapCompiler.resources
    local tracked = {}
    local listing = assert(io.popen(("git -C '%s' ls-files"):format(ROOT)))
    for path in listing:lines() do
        tracked[#tracked + 1] = path
    end
    listing:close()
    assert(#tracked > 0, "the tree this runs in is not a git checkout")

    local sources = {}
    for _, resource in ipairs(resources) do
        local pattern = type(resource) == "table" and resource.source or resource
        if pattern:find("*", 1, true) then
            -- A glob names whatever is there now, which is the set a build embeds.
            local escaped = pattern:gsub("[%%%.%+%-%(%)%[%]%^%$%?]", "%%%0")
            local matcher = "^" .. escaped:gsub("%*", "[^/]*") .. "$"
            for _, path in ipairs(tracked) do
                if path:match(matcher) then
                    sources[#sources + 1] = path
                end
            end
        else
            sources[#sources + 1] = pattern
        end
    end
    assert(#sources > 0, "the stage-zero target embeds nothing")

    local query = ("git -C '%s' check-attr eol --"):format(ROOT)
    for _, path in ipairs(sources) do
        query = query .. " '" .. path .. "'"
    end
    local unspelled = {}
    local attributes = assert(io.popen(query))
    for line in attributes:lines() do
        local path, value = line:match("^(.*): eol: (%S+)$")
        if path and value ~= "lf" then
            unspelled[#unspelled + 1] = path
        end
    end
    attributes:close()
    assert(#unspelled == 0, "embedded resources with no eol=lf in .gitattributes: " .. table.concat(unspelled, ", "))
end

return M
