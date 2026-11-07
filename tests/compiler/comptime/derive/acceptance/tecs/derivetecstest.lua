local fixture = require("helpers.deriveacceptance")
local run = fixture.run

local M = {}

function M.runsTheExternalTecsMCPRequestCorpus()
    local result = run(
        [[
-- Proving case adapted from tecs.io.mcp.transport.Request. Its private loader.CPtr
-- handle is intentionally outside JSON; the constrained result model refuses it.
@derive(types.debug)
local record TecsMCPRequest
    name: string
    arguments: string
end

local corpus = {
    TecsMCPRequest(name = "world.list", arguments = "{}"),
    TecsMCPRequest(
        name = "world.spawn",
        arguments = '{"components":["Position","Velocity"]}'
    ),
    TecsMCPRequest(
        name = "session.inspect",
        arguments = '{"entity":42,"fields":["name"]}'
    ),
}
local bytes, debugged = {}, {}
local accepted = true
local out = byteapi.Buffer.create()
for index, request in ipairs(corpus) do
    local writer = typedJSON.Writer.of(out)
    typedJSON.writevalue(serde.binding(TecsMCPRequest), request, writer)
    writer:close()
    bytes[index] = out:tostring()
    out:reset()
    debugged[index] = request:debug()
    local decoded, why = decode(serde.binding(TecsMCPRequest), bytes[index])
    accepted = accepted and decoded ~= nil and why == nil
        and (decoded as TecsMCPRequest).name == request.name
        and (decoded as TecsMCPRequest).arguments == request.arguments
end
local malformed, failure = decode(serde.binding(TecsMCPRequest),
    '{"name":"world.list","arguments":"{}","_handle":1}'
)
return {
    bytes = bytes,
    debugged = debugged,
    accepted = accepted,
    malformed = malformed,
    failure = failure,
}
]]
    )
    assert(result.accepted, "the Tecs request corpus did not round-trip")
    assert(result.bytes[1] == '{"name":"world.list","arguments":"{}"}', "Tecs request bytes are not deterministic")
    assert(
        result.debugged[1] == 'TecsMCPRequest { name = "world.list", arguments = "{}" }',
        "Tecs request debug output changed"
    )
    assert(
        result.malformed == nil and result.failure:find("_handle", 1, true),
        "the proving case silently admitted Tecs's private pointer field"
    )
end

return M
