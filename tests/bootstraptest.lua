-- The repository must remain runnable when the ignored build tree is absent.
--
-- What it starts from then is the VM compiler: the one installed in the
-- checkout, or one `bin/nupp` builds from the stage-zero image
-- `scripts/toolchain stage0-image` fetches and verifies against the digest
-- pinned in `scripts/toolchain.pins`. The image is not in the tree, so these
-- cases ask the toolchain for it rather than reading a file.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = HERE .. "/.."

local M = {}

-- What these cases watch is the launcher choosing between the compilers a tree
-- has. A VM compiler selected for the whole run -- the environment a VM-hosted
-- suite inherits -- would answer every command before that choice is made.
local NO_VM_CLI = "NUPP_VM_CLI_IMAGE= NUPP_VM_BINARY="

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

-- The digest is what authenticates the image, so it is the one thing about the
-- bootstrap that is committed. A pin whose digest does not describe the file the
-- toolchain installed means one of them moved without the other.
function M.thePinnedDigestDescribesTheFetchedImage()
    local pins = assert(readFile(ROOT .. "/scripts/toolchain.pins"))
    local pinned = pins:match("\nSTAGE0_IMAGE_SHA256=(%x+)")
    assert(pinned and #pinned == 64, "scripts/toolchain.pins carries no stage-zero image digest")
    assert(pins:match("\nSTAGE0_IMAGE_TAG=(%S+)"), "scripts/toolchain.pins names no stage-zero release")

    local out, ok = capture(("'%s/scripts/toolchain' stage0-image 2>/dev/null"):format(ROOT))
    local path = ok and out:match("([^\n]+)%s*$") or nil
    assert(path, "no stage-zero image; run scripts/toolchain stage0-image")
    local found = capture(("shasum -a 256 '%s' 2>/dev/null || sha256sum '%s'"):format(path, path))
    assert(found:match("^(%x+)") == pinned, "the installed stage-zero image does not have the pinned digest: " .. found)
end

-- A tree carrying the launcher and two compilers that do nothing but say which
-- one they are: a LuaJIT build, and an installed VM compiler whose runtime is a
-- script. What these cases test is the launcher's choice between them and what
-- it waits for on the way, and a real pair would take a build to produce and
-- answer the same question.
--
-- The Rust native provider is planted rather than built for the same reason: the
-- launcher stages one before every command that reads a source, and this tree
-- has no `runtime` to build one from. Planted under all three platform names,
-- because which one is looked for is decided by `uname` and none of them is
-- ever opened.
--
-- `vmBody` is shell run with the command's arguments, in the tree.
local function plantedTree(vmBody)
    local dir = os.tmpname()
    os.remove(dir)
    local generation = ("a"):rep(64)
    local package = dir .. "/.nupp/vm-cli/" .. generation
    assert(
        os.execute(
            ("mkdir -p '%s/bin' '%s/build/nupp/tools' '%s/build/lib' '%s/toolchain' '%s'"):format(
                dir,
                dir,
                dir,
                dir,
                package
            )
        ) == 0
    )
    assert(os.execute(("cp '%s/bin/nupp' '%s/bin/nupp'"):format(ROOT, dir)) == 0)
    assert(os.execute(("cp -R '%s/scripts' '%s/scripts'"):format(ROOT, dir)) == 0)

    local function plant(path, text)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    plant("build/nupp/tools/main.lua", 'print("BUILT")\n')
    plant(".nupp/vm-cli/current", generation .. "\n")
    plant(".nupp/vm-cli/" .. generation .. "/format", "nupp-vm-cli-1\n")
    plant(".nupp/vm-cli/" .. generation .. "/compiler.image", "")
    -- Called as `runtime exec IMAGE nupp.tools.vm.root ARG...`.
    plant(
        ".nupp/vm-cli/" .. generation .. "/runtime",
        "#!/bin/sh\nshift 3\n" .. (vmBody or 'echo VM\necho "NUPP_ENGINE=${NUPP_ENGINE:-}"\n')
    )
    assert(os.execute(("chmod +x '%s/runtime'"):format(package)) == 0)

    -- Last, because the launcher stages a provider again whenever anything it is
    -- keyed on is newer than the library -- and the pins file is one of those.
    -- Staged for real, this tree has no `rust-toolchain.toml` to name a toolchain
    -- with, so the build these cases are watching never starts.
    for _, name in ipairs({"libnupp_native_dev.dylib", "libnupp_native_dev.so", "nupp_native_dev.dll",}) do
        plant("build/lib/" .. name, "")
    end

    local env = ("%s NUPP_VM_AUTO_REBUILD=0 NUPP_TOOLCHAIN_DIR='%s/toolchain' NUPP_HOST_OFFLINE=1"):format(
        NO_VM_CLI,
        dir
    )

    local prefix = capture(("%s '%s/scripts/toolchain' --prefix"):format(env, dir)):match("([^\n]+)%s*$")
    assert(prefix)
    assert(os.execute(("mkdir -p '%s/luajit/bin'"):format(prefix)) == 0)
    local interpreter = capture("command -v luajit"):match("([^\n]+)%s*$")
    assert(interpreter)
    assert(os.execute(("ln -s '%s' '%s/luajit/bin/luajit'"):format(interpreter, prefix)) == 0)
    local complete = assert(io.open(prefix .. "/luajit/.complete", "wb"))
    complete:close()
    -- And the receipt an install leaves, which the toolchain checks the
    -- interpreter against before it believes the marker.
    assert(
        os.execute(
            (
                "{ cksum < '%s/scripts/patches/luajit.patch'; cksum < '%s/luajit/bin/luajit'; }"
                    .. " > '%s/luajit/.nupp-runtime-patch'"
            ):format(dir, prefix, prefix)
        ) == 0
    )

    return dir, plant, env
end

-- What the LuaJIT path asks, under NUPP_ENGINE=luajit, which is how a command
-- reaches it in a tree that has a VM compiler installed.
local function ran(dir, env, command)
    local out = capture(("cd '%s' && %s NUPP_ENGINE=luajit ./bin/nupp %s 2>&1"):format(dir, env, command))
    return out
end

-- A tree with no LuaJIT build is built by the VM compiler, asked through the
-- launcher with the engine choice cleared so it does not come back here.
function M.aTreeWithNoLuaJITBuildIsBuiltByTheVmCompiler()
    local dir, _, env = plantedTree([=[
echo "VM $1 NUPP_ENGINE=${NUPP_ENGINE:-}"
printf 'print("BUILT")\n' > build/nupp/tools/main.lua
]=])
    assert(os.remove(dir .. "/build/nupp/tools/main.lua"))
    local output = ran(dir, env, "build")
    assert(output:find("VM build NUPP_ENGINE=\n", 1, true), output)
    assert(readFile(dir .. "/build/nupp/tools/main.lua"), "the VM build wrote no compiler: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

-- Which compiler a command runs is decided on whether one is there, not on
-- whether the completion stamp says the last build finished. Those two differ
-- for the length of every build, because a build removes the stamp before it
-- writes anything -- and a command answering "no compiler here" then runs a
-- different compiler with a different digest. Every content key a build writes
-- carries that digest, so a project whose native library one of them linked
-- relinks under the other with nothing changed.
function M.aStamplessTreeStillRunsTheCompilerItHas()
    local dir, _, env = plantedTree()

    -- `--help` reads no source, so what it prints is the choice and nothing else.
    assert(
        ran(dir, env, "--help"):find("BUILT", 1, true),
        "a build in progress has removed the stamp, and the compiler it is rewriting "
        .. "is still a better answer than another one"
    )

    local stamp = assert(io.open(dir .. "/build/.nupp-complete", "wb"))
    stamp:write("complete\n")
    stamp:close()
    assert(ran(dir, env, "--help"):find("BUILT", 1, true), "and is the answer once the stamp is back")

    assert(os.remove(dir .. "/build/nupp/tools/main.lua"))
    assert(
        ran(dir, env, "--help"):find("VM", 1, true),
        "the VM compiler is for a tree that has no LuaJIT build, not for one mid-build"
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
      %s NUPP_ENGINE=luajit ./bin/nupp build > ran.txt 2>&1 &
      sleep 2
      printf 'while held: [%%s]\n' "$(cat ran.txt)"
      wait
      printf 'after: [%%s]\n' "$(cat ran.txt)"
   ]]
    ):format(dir, env)
    local out = capture(script .. " 2>&1")

    -- What the lock decides is whether the compiler ran, and "BUILT" is the
    -- planted compiler saying it did. Asserting no bytes at all asserted
    -- something else as well: the launcher stages a provider before it reaches
    -- the lock, and in a tree planted without a Rust toolchain that stage has
    -- something to say -- so a run that held the lock correctly still reported
    -- it as broken.
    local held = out:match("while held: %[(.-)%]\n") or "<no line>"
    assert(not held:find("BUILT", 1, true), "a build ran while another held the lock: " .. out)
    assert(out:find("after: [BUILT]", 1, true), "and did not run once the lock was free: " .. out)

    os.execute("rm -rf '" .. dir .. "'")
end

-- A built compiler that cannot build falls back to the VM compiler, and the
-- module bytecode cache goes with it. An entry that is damaged but still loads
-- fails the built compiler the same way on every run, so keeping it left `nupp
-- clean` -- all of build/, the Rust tree with it -- as the only way out.
function M.aFallbackDropsTheBytecodeTheBuiltCompilerLoaded()
    local dir, plant, env = plantedTree(
        'if [ -f build/.bytecode/index ]; then echo "VM bytecode=present"; else echo "VM bytecode=absent"; fi\n'
    )
    plant("build/nupp/tools/main.lua", 'if arg[1] == "build" then os.exit(3) end\nprint("BUILT")\n')
    assert(os.execute(("mkdir -p '%s/build/.bytecode'"):format(dir)) == 0)
    plant("build/.bytecode/index", "damaged")

    local out = ran(dir, env, "check")
    assert(out:find("falling back to the VM compiler", 1, true), out)
    assert(out:find("VM bytecode=absent", 1, true), "the VM compiler ran beside the damaged cache: " .. out)

    os.execute("rm -rf '" .. dir .. "'")
end

-- The cached image went in verified, and was then believed for being there. A
-- disk that damaged it afterwards got the damage run as the compiler.
function M.aDamagedCachedStageZeroImageIsFetchedAgain()
    local dir, plant, env = plantedTree()
    local pins = assert(readFile(dir .. "/scripts/toolchain.pins"))
    local tag = assert(pins:match("\nSTAGE0_IMAGE_TAG=(%S+)"), "no stage-zero image is pinned")
    plant("planted.image", "a planted stage-zero image\n")
    local digest = capture(
        ("shasum -a 256 '%s/planted.image' 2>/dev/null || sha256sum '%s/planted.image'"):format(dir, dir)
    ):match("^(%x+)")
    assert(os.execute(("mkdir -p '%s/supplied'"):format(dir)) == 0)
    assert(
        os.execute(
            ("gzip -c '%s/planted.image' > '%s/supplied/nupp-stage0-%s.image.gz'"):format(dir, dir, tag)
        ) == 0
    )
    plant("scripts/toolchain.pins", (pins:gsub("\nSTAGE0_IMAGE_SHA256=%x+", "\nSTAGE0_IMAGE_SHA256=" .. digest)))

    local toolchain = ("%s NUPP_HOST_SOURCE_DIR='%s/supplied' '%s/scripts/toolchain' stage0-image 2>&1"):format(
        env,
        dir,
        dir
    )
    local out, ok = capture(toolchain)
    assert(ok, "the planted stage-zero image did not install: " .. out)
    local cached = dir .. "/toolchain/stage0-image/" .. digest .. "/compiler.image"
    local planted = assert(readFile(dir .. "/planted.image"))
    assert(readFile(cached) == planted, "the stage-zero image was not cached where this case looks")

    local damaged = assert(io.open(cached, "wb"))
    damaged:write(planted:sub(1, math.floor(#planted / 2)))
    damaged:close()
    out, ok = capture(toolchain)
    assert(ok, "a damaged cached stage-zero image was not replaced: " .. out)
    assert(out:find("fetching it again", 1, true), "the damage was not reported: " .. out)
    assert(readFile(cached) == planted, "the cached stage-zero image is still damaged")

    os.execute("rm -rf '" .. dir .. "'")
end

-- Every resource the compiler carries is embedded verbatim, so a checkout that
-- translates line endings composes a stage-zero image whose bytes cannot
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
    assert(#sources > 0, "the compiler embeds nothing")

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
