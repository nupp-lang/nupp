-- External D6 proving provider. This process deliberately has no compiler
-- modules in its protocol: it reads one JSON descriptor and writes one JSON
-- semantic-result envelope.

local json = require("cjson.safe")

local MAX_INPUT_BYTES = 65536

local input = io.read("*a")
if #input > MAX_INPUT_BYTES then
    io.stderr:write("derive descriptor exceeds the prototype input limit\n")
    os.exit(2)
end

local descriptor, why = json.decode(input)
if type(descriptor) ~= "table" then
    io.stderr:write("cannot decode derive descriptor: " .. tostring(why) .. "\n")
    os.exit(2)
end
if descriptor.protocol ~= "nupp.derive.prototype" or descriptor.version ~= 1 or type(
    descriptor.fingerprint
) ~= "string" or type(
    descriptor.provider
) ~= "table" or descriptor.provider.identity ~= "tecs.io.mcp/redacted-debug" or descriptor.provider.abi ~= 1 or type(
    descriptor.target
) ~= "table" or descriptor.target.kind ~= "record" or type(
    descriptor.target.identity
) ~= "string" or type(descriptor.target.fields) ~= "table" then
    io.stderr:write("unsupported derive descriptor\n")
    os.exit(2)
end

local fields = {}
for _, field in ipairs(descriptor.target.fields) do
    local sensitive = false
    for _, annotation in ipairs(field.annotations or {}) do
        if annotation == "tecs.io.mcp/sensitive" then
            sensitive = true
        end
    end
    fields[
        #fields + 1
    ] = {source = field.name, render = sensitive and {kind = "literal", value = "<redacted>"} or {kind = "value"},}
end

local result = {
    protocol = "nupp.derive.prototype",
    version = 1,
    fingerprint = descriptor.fingerprint,
    provider = descriptor.provider,
    target = descriptor.target.identity,
    additions = {{operation = "debug.record.v1", member = "debug", contract = "nupp.Debug", fields = fields,}},
}

local output, encodeError = json.encode(result)
if not output then
    io.stderr:write("cannot encode derive result: " .. tostring(encodeError) .. "\n")
    os.exit(2)
end
io.write(output, "\n")
