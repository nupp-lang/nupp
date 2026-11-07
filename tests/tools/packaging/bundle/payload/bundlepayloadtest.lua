local fixture = require("helpers.bundlefixture")
local packaging = fixture.packaging

local M = {}

-- Precompiling is a change to the shape of a payload, and the two things it must
-- not change are what the payload does and what it is called. Code in a bundle
-- finds what travels beside the binary -- the native library, an AOT builder, the
-- compiler's staged declarations -- by reading the chunk name, and the host settles
-- that name from the executable it found itself in. A dump that kept its debug
-- information would answer with a name settled where it was built instead.
function M.aPayloadForThisMachineIsStrippedBytecodeTheHostStillNames()
    local source = "return debug.getinfo(1, 'S').source\n"
    local bytes, flags = packaging.payloadBytes(source, nil)
    assert(bytes, "a payload is produced for this machine")
    assert(flags == packaging.payloadFlagBytecode, "and its trailer says it carries bytecode")
    assert(bytes:sub(1, 3) == "\27LJ", "which is what it is")

    local chunk = assert(loadstring(bytes, "@/somewhere/nupp"))
    assert(chunk() == "@/somewhere/nupp", "the name comes from whoever loads it, as it does for a source payload")
end

-- A dump records the endianness and VM configuration it was written for and is
-- refused by one that does not match. A cross-stamped binary is run by a VM this
-- machine never sees, so it carries the bundle itself, which any of them can read.
function M.aPayloadForAnotherPlatformStaysSource()
    local platform = require("nupp.tools.build.platform")
    local elsewhere
    for _, key in ipairs(platform.keys()) do
        if key ~= platform.hostKey() then
            elsewhere = key
            break
        end
    end
    assert(elsewhere, "the platform list names somewhere this is not")

    local source = "return 1\n"
    local bytes, flags = packaging.payloadBytes(source, elsewhere)
    assert(bytes == source, "a cross-stamped payload is the bundle itself")
    assert(flags == 0, "and its trailer says so")
end

return M
