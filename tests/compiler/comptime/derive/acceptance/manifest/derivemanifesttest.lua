local fixture = require("helpers.deriveacceptance")
local run = fixture.run

local M = {}

function M.matchesManifestAndBuildCacheJSONCorpora()
    local result = run(
        [[
local record ModuleCache
    sourceHash: string
    interfaceHash: string
    dependencies: {string}
    effects: {string}
    external: boolean = false
end

local corpora = {
    ModuleCache(
        sourceHash = "source-a",
        interfaceHash = "interface-a",
        dependencies = {"nupp.compiler.types", "nupp.compiler.project.env"},
        effects = {"stdlib.derives"},
        external = false
    ),
    ModuleCache(
        sourceHash = "source-b",
        interfaceHash = "interface-b",
        dependencies = {},
        effects = {"native.json", "stdlib.derives"},
        external = true
    ),
}
local bytes = {}
local accepted = true
local out = byteapi.Buffer.create()
for index, value in ipairs(corpora) do
    local writer = typedJSON.Writer.of(out)
    typedJSON.writevalue(serde.binding(ModuleCache), value, writer)
    writer:close()
    bytes[index] = out:tostring()
    out:reset()
    local decoded, why = decode(serde.binding(ModuleCache), bytes[index])
    accepted = accepted and decoded ~= nil and why == nil
        and (decoded as ModuleCache).sourceHash == value.sourceHash
        and (decoded as ModuleCache).interfaceHash == value.interfaceHash
end
local rejected, failure = decode(serde.binding(ModuleCache),
    '{"sourceHash":"x","interfaceHash":"y","dependencies":[],"effects":[],"extra":1}'
)
return {bytes = bytes, accepted = accepted, rejected = rejected, failure = failure}
]]
    )
    assert(result.accepted, "the build-cache corpus did not round-trip")
    assert(
        result.bytes[
            1
        ] == '{"sourceHash":"source-a","interfaceHash":"interface-a",'
        .. '"dependencies":["nupp.compiler.types","nupp.compiler.project.env"],'
        .. '"effects":["stdlib.derives"],"external":false}',
        "derived manifest bytes differ from the pinned ordering"
    )
    assert(
        result.bytes[
            2
        ] == '{"sourceHash":"source-b","interfaceHash":"interface-b",'
        .. '"dependencies":[],"effects":["native.json","stdlib.derives"],'
        .. '"external":true}',
        "derived cache bytes differ from the pinned ordering"
    )
    assert(
        result.rejected == nil and result.failure:find("unknown member", 1, true),
        "strict manifest validation accepted an unknown key"
    )
end

return M
