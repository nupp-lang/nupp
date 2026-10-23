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
    local resources = manifest.build.targets.compiler.resources
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
