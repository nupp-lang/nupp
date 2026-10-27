-- Bootstrap execution uses a verified runtime/image pair. The machine bridge
-- may decode images and emit objects; it never supplies the execution loop.
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."
local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(("cd %s && %s 2>&1; echo __exit__:$?"):format(quote(ROOT), command)))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))

    return status, output:gsub("__exit__:%d+%s*$", "")
end

local function pair()
    local status, output = capture("./scripts/toolchain stage0-seed")
    assert(status == 0, "no verified bootstrap execution seed: " .. output)
    return assert(output:match("([^\r\n]+)%s*$"))
end

function M.thePinnedSeedExecutesItsMatchingCompilerWithoutAot()
    local seed = pair()
    local status, output = capture("python3 scripts/bootstrap-seed verify " .. quote(seed) .. " --execute")
    assert(status == 0, output)
    -- A second fetch rechecks both artifact digests without downloading or building.
    assert(pair() == seed, "warm bootstrap selected a different seed pair")
end

function M.thePinnedSeedExecutesANewlyEmittedImageWithoutARustBuild()
    local seed = pair()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p " .. quote(dir .. "/src")) == 0)
    local source = assert(io.open(dir .. "/src/bootstrapprobe.nupp", "wb"))
    source:write(
        [=[module bootstrapprobe
local probe = {}
function probe.answer(): string
    local values: {integer} = {40, 2}
    collectgarbage("collect")
    return tostring(values[1] + values[2])
end
export = probe
]=]
    )
    source:close()
    local image = dir .. "/probe.image"
    local command = "python3 scripts/bootstrap-seed run " .. quote(seed)
    local status, output = capture(
        command .. " run " .. quote(
            seed .. "/compiler.image"
        ) .. " nupp.tools.vm.project emit " .. quote(dir) .. " bootstrapprobe '' src --output " .. quote(image)
    )
    assert(status == 0, "the seed failed to emit fresh source: " .. output)
    status, output = capture(command .. " run " .. quote(image) .. " bootstrapprobe answer")
    assert(status == 0, "the seed failed to execute the newly emitted image: " .. output)
    assert(output:match('^"42"[\r\n]'), "the newly emitted image answered incorrectly: " .. output)
    assert(os.execute("rm -rf " .. quote(dir)) == 0)
end

return M
