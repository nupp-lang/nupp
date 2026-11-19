-- The repository must remain runnable when the ignored build tree is absent.
--
-- What it starts from then is the VM compiler: the one installed in the
-- checkout, or one `bin/nupp` builds from the stage-zero image
-- `scripts/toolchain stage0-image` fetches and verifies against the digest
-- pinned in `scripts/toolchain.pins`. The image is not in the tree, so these
-- cases ask the toolchain for it rather than reading a file.
local HERE = require("helpers.paths").absoluteTests
local ROOT = HERE .. "/.."

local M = {}

-- A VM compiler selected for the whole run -- the environment a VM-hosted suite
-- inherits -- is cleared for the toolchain these cases ask.
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

-- A tree holding a copy of the scripts, with a toolchain cache of its own, so a
-- case can plant what the toolchain finds there.
local function stageZeroTree()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p '%s/toolchain'"):format(dir)) == 0)
    assert(os.execute(("cp -R '%s/scripts' '%s/scripts'"):format(ROOT, dir)) == 0)

    local function plant(path, text)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    local env = ("%s NUPP_TOOLCHAIN_DIR='%s/toolchain' NUPP_HOST_OFFLINE=1"):format(NO_VM_CLI, dir)

    return dir, plant, env
end

-- The cached image went in verified, and was then believed for being there. A
-- disk that damaged it afterwards got the damage run as the compiler.
function M.aDamagedCachedStageZeroImageIsFetchedAgain()
    local dir, plant, env = stageZeroTree()
    local pins = assert(readFile(dir .. "/scripts/toolchain.pins"))
    local tag = assert(pins:match("\nSTAGE0_IMAGE_TAG=(%S+)"), "no stage-zero image is pinned")
    plant("planted.image", "a planted stage-zero image\n")
    local digest = capture(
        ("shasum -a 256 '%s/planted.image' 2>/dev/null || sha256sum '%s/planted.image'"):format(dir, dir)
    )
        :match("^(%x+)")
    assert(os.execute(("mkdir -p '%s/supplied'"):format(dir)) == 0)
    assert(
        os.execute(("gzip -c '%s/planted.image' > '%s/supplied/nupp-stage0-%s.image.gz'"):format(dir, dir, tag)) == 0
    )
    plant("scripts/toolchain.pins", (pins:gsub("\nSTAGE0_IMAGE_SHA256=%x+", "\nSTAGE0_IMAGE_SHA256=" .. digest)))

    local toolchain = (
        "%s NUPP_HOST_SOURCE_DIR='%s/supplied' '%s/scripts/toolchain' stage0-image 2>&1"
    ):format(env, dir, dir)
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
    local resources = manifest.build.targets[manifest.selfHost.target].resources
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

function M.nativeCompilerResourcesCarryTheCliTestHarness()
    local targets = assert(loadfile(ROOT .. "/nupp.lua"))().build.targets
    for _, name in ipairs({"dist", "testRunner"}) do
        local target = assert(targets[name])
        assert(target.kind == "binary" and target.stub == "nupp")
        local found = {}
        for _, resource in ipairs(target.resources) do
            local path = type(resource) == "table" and resource.source or resource
            found[path] = true
        end
        assert(found["tests/run.lua"] and found["tests/cache.lua"], name .. " omits the CLI test harness")
    end
end

-- The C codecs the VM's providers bind as the core does.
local SHARED_CORE = {
    ["src/nupp/runtime/core/compressioncodec.nupp"] = true,
    ["src/nupp/runtime/core/crccodec.nupp"] = true,
}

-- The runner's sources name the trees beside the native core one by one, so a
-- tree added to src has to join them for a suite to load its modules.
function M.theTestRunnerCarriesEverySourceButTheNativeCore()
    local glob = require("nupp.compiler.shellsyntax").glob
    local matchers = {}
    for _, source in ipairs(assert(loadfile(ROOT .. "/nupp.lua"))().build.targets.testRunner.sources) do
        matchers[#matchers + 1] = glob(source)
    end
    local listing = assert(io.popen("git -C '" .. ROOT .. "' ls-files src"))
    local missing, carried, checked = {}, {}, 0
    for path in listing:lines() do
        if path:match("%.nupp$") and not path:match("%.d%.nupp$") then
            checked = checked + 1
            local core = (path:match("^src/nupp/runtime/core/") or path:match("^src/nupp/core/"))
                and not SHARED_CORE[path]
            local matched = false
            for _, matches in ipairs(matchers) do
                matched = matched or matches(path)
            end
            if core and matched then
                carried[#carried + 1] = path
            elseif not core and not matched then
                missing[#missing + 1] = path
            end
        end
    end
    listing:close()
    assert(checked > 100, "src lists too few sources to be the tree")
    assert(#missing == 0, "the test runner omits:\n  " .. table.concat(missing, "\n  "))
    assert(#carried == 0, "the test runner carries the native core:\n  " .. table.concat(carried, "\n  "))
end

-- The core seed: the compiler and C bridge pair `nupp fixpoint --runtime core
-- --package-seed` packages (`nupp.tools.vm.packaging.coreSeed`), and
-- `scripts/toolchain core-seed-install` installs cold. The pair here is a
-- stand-in: a runtime that answers as the C bridge does, and runs any bundle
-- as a compiler that knows `--help`.
local CORE_RUNTIME = [=[#!/bin/sh
if [ "$#" -lt 3 ]; then
    echo 'nupp-core: usage: nupp-core BUNDLE INPUT OUTPUT [ARGUMENT...]' >&2
    exit 1
fi
[ "$4" = --help ] && echo 'Usage: nupp COMMAND'
exit 0
]=]

local function coreHost()
    local host = capture(("sh '%s/scripts/stage0-runtime' --host"):format(ROOT)):match("^(%S+)")
    if host == "unsupported" then
        require("assert").suite.skip("the native core runs on ARM64 macOS and Linux only")
    end
end

-- A packaged stand-in seed, and a toolchain cache of its own to install it in;
-- with `library`, the compiler carries lib/libnuppffi beside it.
local function packagedSeed(library)
    coreHost()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p '%s/pair'"):format(dir)) == 0)

    local function plant(path, text)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    plant("pair/runtime", CORE_RUNTIME)
    assert(os.execute(("chmod 755 '%s/pair/runtime'"):format(dir)) == 0)
    plant("pair/compiler.bundle", "NUPPCORE" .. string.rep("\0", 64) .. "a compiler")
    if library then
        assert(os.execute(("mkdir -p '%s/pair/lib'"):format(dir)) == 0)
        plant("pair/lib/libnuppffi", "a library\n")
    end
    local seed, problem = require(
        "nupp.tools.vm.packaging"
    ).coreSeed(ROOT, dir .. "/pair/runtime", dir .. "/pair/compiler.bundle", "test", dir .. "/seed")
    assert(seed, problem)

    local function install(archive, digest)
        return capture(
            (
                "%s NUPP_TOOLCHAIN_DIR='%s/toolchain' NUPP_HOST_OFFLINE=1 sh '%s/scripts/toolchain' core-seed-install '%s' %s 2>&1"
            ):format(NO_VM_CLI, dir, ROOT, archive, digest)
        )
    end

    -- The seed's archive rebuilt with `change` applied to its files.
    local function repacked(change)
        local unpacked = dir .. "/unpacked"
        assert(
            os.execute(
                (
                    "rm -rf '%s' && mkdir -p '%s' && tar -xzf '%s' -C '%s'"
                ):format(unpacked, unpacked, seed.archive, unpacked)
            ) == 0
        )
        change(unpacked)
        local archive = dir .. "/repacked.tar.gz"
        os.remove(archive)
        assert(
            os.execute(("sh '%s/scripts/toolchain' archive '%s' '%s' > /dev/null"):format(ROOT, unpacked, archive)) == 0
        )
        local digest = capture(("shasum -a 256 '%s' 2>/dev/null || sha256sum '%s'"):format(archive, archive))
            :match("^(%x+)")

        return archive, digest
    end

    return dir, seed, install, repacked
end

function M.aPackagedCoreSeedInstallsColdAndRuns()
    local dir, seed, install = packagedSeed()
    local sum = assert(readFile(seed.archive .. ".sha256"))
    assert(sum:match("^(%x+)") == seed.sha256, "the archive's digest is not beside it: " .. sum)
    assert(seed.archive:match("/nupp%-core%-seed%-[%w_-]+%-test%.tar%.gz$"), seed.archive)
    local listing = capture(("tar -tzf '%s'"):format(seed.archive))
    assert(listing == "NOTICE.md\ncompiler.bundle\nmanifest.json\nruntime\n", listing)
    local again = require(
        "nupp.tools.vm.packaging"
    ).coreSeed(ROOT, dir .. "/pair/runtime", dir .. "/pair/compiler.bundle", "test", dir .. "/seed")
    assert(again == nil, "a packaged seed archive was replaced")

    local out = install(seed.archive, seed.sha256)
    local installed = out:match("([^\n]+)\n?$")
    assert(installed == dir .. "/toolchain/core-seed/" .. seed.sha256, "the seed did not install: " .. out)
    assert(readFile(installed .. "/compiler.bundle") == readFile(dir .. "/pair/compiler.bundle"))
    assert(readFile(installed .. "/manifest.json"):find('"format": "nupp-core-seed-1"', 1, true))
    assert(install("/nonexistent", seed.sha256) == out, "the installed seed is not reused from the cache")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A compiler that loads libffi relative to itself takes it into its seed.
function M.aCoreSeedCarriesTheLibrariesBesideItsCompiler()
    local dir, seed, install = packagedSeed(true)
    local listing = capture(("tar -tzf '%s'"):format(seed.archive))
    assert(listing == "NOTICE.md\ncompiler.bundle\nlib/libnuppffi\nmanifest.json\nruntime\n", listing)
    local out = install(seed.archive, seed.sha256)
    local installed = out:match("([^\n]+)\n?$")
    assert(installed == dir .. "/toolchain/core-seed/" .. seed.sha256, "the seed did not install: " .. out)
    assert(readFile(installed .. "/lib/libnuppffi") == "a library\n", "the library did not install beside it")
    os.execute("rm -rf '" .. dir .. "'")
end

-- scripts/core-cli keeps its generations in a store worktrees share, by the
-- compiler sources each was built from: a checkout with the same sources
-- selects one with no build, and only sources no generation was built from
-- build. The build here is a stand-in that counts itself.
function M.coreCompilerGenerationsAreSharedBySources()
    coreHost()
    local dir = os.tmpname()
    os.remove(dir)

    local function plant(path, text, mode)
        assert(os.execute(("mkdir -p \"$(dirname '%s/%s')\""):format(dir, path)) == 0)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
        if mode then
            assert(os.execute(("chmod %s '%s/%s'"):format(mode, dir, path)) == 0)
        end
    end

    local selfBuild = table.concat(
        {
            "#!/bin/sh",
            "set -eu",
            'out=$4; mkdir -p "$out"',
            ("count=$(cat '%s/builds' 2>/dev/null || echo 0); echo $((count + 1)) > '%s/builds'"):format(dir, dir),
            ('printf "%%s\\n" "$3" >> %q'):format(dir .. "/builders"),
            'printf "NUPPCORE%s" "$(cat "$(dirname "$0")/../src/a.nupp")" > "$out/compiler.bundle"',
            ("cp '%s/runtime' \"$out/runtime\""):format(dir),
            "",
        },
        "\n"
    )
    plant("runtime", CORE_RUNTIME, "755")
    plant("seed.bundle", "NUPPCORE seed")
    for _, checkout in ipairs({"a", "b"}) do
        plant(checkout .. "/bin/nupp", assert(readFile(ROOT .. "/bin/nupp")), "755")
        plant(checkout .. "/scripts/core-cli", assert(readFile(ROOT .. "/scripts/core-cli")), "755")
        plant(checkout .. "/scripts/lock-owner", assert(readFile(ROOT .. "/scripts/lock-owner")), "755")
        local runtime = checkout == "a" and "core" or "vm"
        plant(
            checkout .. "/scripts/stage0-runtime",
            ("#!/bin/sh\nif [ \"$1\" = --host ]; then echo aarch64-apple-darwin; else echo %s; fi\n"):format(runtime),
            "755"
        )
        plant(checkout .. "/scripts/toolchain.pins", "STAGE0_CORE_SHA256_AARCH64_APPLE_DARWIN=first\n")
        plant(
            checkout .. "/scripts/toolchain",
            ("#!/bin/sh\n[ \"$1\" = core-seed ] && echo %q\n"):format(dir .. "/seed"),
            "755"
        )
        plant(checkout .. "/scripts/core-self-build", selfBuild, "755")
        plant(checkout .. "/src/a.nupp", "one\n")
        -- Its sources are what git would track.
        assert(os.execute(("git -C '%s/%s' init -q"):format(dir, checkout)) == 0)
    end

    local function cli(checkout, arguments)
        local command = "scripts/core-cli"
        if arguments:sub(1, 4) == "run " then
            command, arguments = "bin/nupp", arguments:sub(5)
        end

        return capture(
            (
                "%s NUPP_RUNTIME=core NUPP_CORE_AUTO_REBUILD=1 NUPP_CORE_CLI_STORE='%s/store' sh '%s/%s/%s' %s 2>&1"
            ):format(NO_VM_CLI, dir, dir, checkout, command, arguments)
        )
    end

    local function builds()
        return tonumber(readFile(dir .. "/builds") or "0")
    end

    local ok, problem = pcall(function()
        cli("a", ("install '%s/runtime' '%s/seed.bundle'"):format(dir, dir))
        cli("a", "build")
        assert(builds() == 1, "checkout a built once")
        local built = readFile(dir .. "/a/.nupp/core-cli/current")
        assert(
            readFile(dir .. "/store/" .. built:gsub("%s+$", "") .. "/format"),
            "the generation is in the shared store"
        )
        cli("b", "select")
        assert(readFile(dir .. "/b/.nupp/core-cli/current") == built, "checkout b selects a's generation")
        assert(builds() == 1, "with no build")
        cli("b", "run version")
        assert(builds() == 1, "running it builds nothing")
        os.execute("sleep 1")
        plant("b/src/a.nupp", "two\n")
        cli("b", "run version")
        assert(builds() == 2, "an edit no generation was built from builds one")
        os.execute("sleep 1")
        plant("b/src/a.nupp", "one\n")
        cli("b", "run version")
        assert(builds() == 2, "sources a generation was built from build nothing again")
        assert(readFile(dir .. "/b/.nupp/core-cli/current") == readFile(dir .. "/a/.nupp/core-cli/current"))
        for _, source in ipairs({"three\n", "four\n"}) do
            os.execute("sleep 1")
            plant("b/src/a.nupp", source)
            cli("b", "run version")
        end
        assert(builds() == 4, "each new source builds once")
        local builders = {}
        for builder in assert(readFile(dir .. "/builders")):gmatch("[^\n]+") do
            builders[#builders + 1] = builder
        end
        assert(#builders == 4 and builders[2] == builders[3] and builders[3] == builders[4], "edits share one builder")
        assert(readFile(builders[4]) == "NUPPCOREone", "the builder remains available after pruning")
        plant("seed/runtime", CORE_RUNTIME, "755")
        plant("seed/compiler.bundle", "NUPPCORE second seed")
        os.execute("sleep 1")
        plant("b/scripts/toolchain.pins", "STAGE0_CORE_SHA256_AARCH64_APPLE_DARWIN=second\n")
        cli("b", "run version")
        assert(builds() == 5, "a new pin bootstraps one generation")
        assert(assert(readFile(dir .. "/builders")):match("([^\n]+)\n$") == dir .. "/seed/compiler.bundle")
        os.execute("sleep 1")
        plant("b/src/a.nupp", "five\n")
        cli("b", "run version")
        assert(builds() == 6, "an edit uses the new generation")
        local afterPin = assert(readFile(dir .. "/builders")):match("([^\n]+)\n$")
        assert(readFile(afterPin) == "NUPPCOREfour", "edits keep the generation bootstrapped by the new pin")
        os.execute("sleep 1")
        assert(os.remove(dir .. "/b/src/a.nupp"))
        cli("b", "run version")
        assert(builds() == 7, "removing a source also rebuilds")
    end)
    os.execute("rm -rf '" .. dir .. "'")
    assert(ok, problem)
end

function M.aCoreSeedArchiveWithAnotherDigestIsRefused()
    local dir, seed, install = packagedSeed()
    local out = install(seed.archive, string.rep("0", 64))
    assert(out:find("refusing to unpack it", 1, true), out)
    assert(readFile(dir .. "/toolchain/core-seed/" .. string.rep("0", 64) .. "/runtime") == nil)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aCoreSeedArchiveWithAnUnnamedEntryIsRefused()
    local dir, _, install, repacked = packagedSeed()
    local archive, digest = repacked(function(unpacked)
        local file = assert(io.open(unpacked .. "/extra", "wb"))
        file:write("not in the seed\n")
        file:close()
    end)
    local out = install(archive, digest)
    assert(out:find("holds unexpected entries", 1, true), out)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aCoreSeedItsManifestDoesNotDescribeIsRefused()
    local dir, _, install, repacked = packagedSeed()
    local archive, digest = repacked(function(unpacked)
        local file = assert(io.open(unpacked .. "/compiler.bundle", "ab"))
        file:write("changed after packaging")
        file:close()
    end)
    local out = install(archive, digest)
    assert(out:find("not the ones its manifest names", 1, true), out)
    os.execute("rm -rf '" .. dir .. "'")
end

-- Once the pins list a host in STAGE0_CORE_HOSTS, its stage zero is the core
-- seed, and the VM seed is not fetched in its place.
function M.aFlippedHostsStageZeroIsNeverTheVmSeed()
    coreHost()
    local dir, plant, env = stageZeroTree()
    local host = capture(("sh '%s/scripts/stage0-runtime' --host"):format(dir)):match("^(%S+)")
    local pins = assert(readFile(dir .. "/scripts/toolchain.pins"))
    -- With its core seed unpinned, a flipped host must fail rather than fall
    -- back to the VM seed.
    pins = pins:gsub("\nSTAGE0_CORE_HOSTS=[^\n]*", "\nSTAGE0_CORE_HOSTS=" .. host)
    pins = pins:gsub("\n(STAGE0_CORE_URL_[%w_]+)=[^\n]*", "\n%1=")
    pins = pins:gsub("\n(STAGE0_CORE_SHA256_[%w_]+)=[^\n]*", "\n%1=")
    plant("scripts/toolchain.pins", pins)
    plant("scripts/bootstrap-seed", "open('" .. dir .. "/vm-seed-fetched', 'w').close()\n")
    local out, ok = capture(("%s '%s/scripts/toolchain' stage0-seed 2>&1"):format(env, dir))
    assert(not ok, "a flipped host with no core seed pinned found a stage zero: " .. out)
    assert(out:find("no core seed is pinned", 1, true), out)
    assert(readFile(dir .. "/vm-seed-fetched") == nil, "a flipped host fetched the VM seed")
    os.execute("rm -rf '" .. dir .. "'")
end

return M
