local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local run = fixture.run
local stampRustHost = fixture.stampRustHost

local M = {}

function M.bufferFreezeSelectsTheEngineAndFeedsReaders()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {default = "app", targets = {app = {
   kind = "binary", stub = "nupp", entries = {"main"}, outDir = "build",
   payloadOutput = "build/app.payload.lua",
}}}}
]],
        [
            "src/main.nupp"
        ] = [[
local function freeze(takes buffer: bytes.Buffer): bytes.SharedBytes
    return buffer:freeze()
end
local function reader(): io.Reader
    local buffer = bytes.Buffer.create("skipabc\0def")
    buffer:skip(4)
    return io.Reader.of(freeze(buffer))
end
local input = reader()
local output = bytes.Buffer.create()
assert(input:readinto(output, 0, 7) == 7)
assert(output:tostring() == "abc\0def")
input:close()
local region = output:freeze()
print(region:tostring() == "abc\0def")
]],
    })
    local built, builtOk = run(dir, "'" .. NUPP .. "' build")
    assert(builtOk, "the byte I/O binary builds: " .. built)
    local output, ranOk = run(dir, stampRustHost(dir, dir .. "/build/app.payload.lua"))
    assert(ranOk and output == "true\n", "buffer freezing selects and uses engine storage: " .. output)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
