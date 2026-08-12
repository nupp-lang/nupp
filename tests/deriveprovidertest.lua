-- D6 evaluation of a user-defined semantic provider. The provider is a separate
-- process and exchanges JSON only; this is a proving prototype, not a public ABI.

local json = require("cjson.safe")
local hash = require("nupp.compiler.build.hash")
local planCodec = require("nupp.compiler.derive_plan")
local process = require("nupp.compiler.build.process")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local PROVIDER = HERE .. "/fixtures/derive_provider/redacted_debug.lua"
local NUPP = HERE .. "/../bin/nupp"
local MAX_ENVELOPE_BYTES = 65536
local MAX_FIELDS = 128
local MAX_LITERAL_BYTES = 256

local function closed(value, names, path)
    if type(value) ~= "table" then
        return nil, path .. " must be an object"
    end
    for name in pairs(value) do
        if not names[name] then
            return nil, path .. " contains unknown field " .. tostring(name)
        end
    end

    return true
end

local function same(left, right)
    local leftBytes = assert(planCodec.canonical(left))
    local rightBytes = assert(planCodec.canonical(right))
    return leftBytes == rightBytes
end

local function descriptor()
    local value = {
        protocol = "nupp.derive.prototype",
        version = 1,
        provider = {identity = "tecs.io.mcp/redacted-debug", abi = 1},
        target = {
            identity = "tecs.io.mcp.transport/Request",
            kind = "record",
            name = "TecsMCPRequest",
            fields = {
                {name = "name", type = {kind = "string"}, annotations = {}},
                {name = "arguments", type = {kind = "string"}, annotations = {"tecs.io.mcp/sensitive"}},
            },
        },
        capabilities = {"debug.record.v1"},
    }
    local canonical = assert(planCodec.canonicalRoot(value))
    value.fingerprint = hash.sha256("nupp.derive.prototype.v1\0" .. canonical)

    return value
end

local function invoke(value)
    local encoded = assert(json.encode(value))
    local input = os.tmpname()
    local file = assert(io.open(input, "wb"))
    assert(file:write(encoded))
    assert(file:close())
    local pipe = assert(io.popen(("luajit %q < %q 2>&1"):format(PROVIDER, input)))
    local output = pipe:read("*a")
    local ok = pipe:close()
    os.remove(input)
    assert(ok, output)
    assert(#output <= MAX_ENVELOPE_BYTES, "provider result exceeds the envelope limit")
    local decoded, why = json.decode(output)
    assert(decoded, why or output)

    return decoded, output
end

local function validate(request, result)
    local ok, why = closed(
        result,
        {protocol = true, version = true, fingerprint = true, provider = true, target = true, additions = true,},
        "result"
    )
    if not ok then
        return nil, why
    end
    if result.protocol ~= "nupp.derive.prototype" or result.version ~= 1 then
        return nil, "result uses an unsupported protocol version"
    end
    if result.fingerprint ~= request.fingerprint then
        return nil, "result does not identify the requested descriptor"
    end
    if not same(result.provider, request.provider) then
        return nil, "result changed the resolved provider identity"
    end
    if result.target ~= request.target.identity then
        return nil, "result changed the resolved target identity"
    end
    if type(result.additions) ~= "table" or #result.additions ~= 1 then
        return nil, "result must contain exactly one semantic addition"
    end

    local addition = result.additions[1]
    ok, why = closed(addition, {operation = true, member = true, contract = true, fields = true,}, "addition")
    if not ok then
        return nil, why
    end
    if addition.operation ~= "debug.record.v1" or addition.member ~= "debug" or addition.contract ~= "nupp.Debug" then
        return nil, "result requested an unsupported semantic addition"
    end
    if type(
        addition.fields
    ) ~= "table" or #addition.fields > MAX_FIELDS or #addition.fields ~= #request.target.fields then
        return nil, "result has an invalid field projection"
    end

    local available, used = {}, {}
    for _, field in ipairs(request.target.fields) do
        available[field.name] = true
    end
    local normalized = {kind = "debugRecord", name = request.target.name, fields = {}}
    for index, field in ipairs(addition.fields) do
        ok, why = closed(field, {source = true, render = true}, "addition.fields[" .. index .. "]")
        if not ok then
            return nil, why
        end
        if not available[field.source] or used[field.source] then
            return nil, "result refers to an absent or repeated field"
        end
        used[field.source] = true
        ok, why = closed(field.render, {kind = true, value = true}, "addition.fields[" .. index .. "].render")
        if not ok then
            return nil, why
        end
        if field.render.kind == "value" then
            if field.render.value ~= nil then
                return nil, "value rendering accepts no payload"
            end
        elseif field.render.kind == "literal" then
            if type(field.render.value) ~= "string" or #field.render.value > MAX_LITERAL_BYTES then
                return nil, "literal rendering requires a bounded string"
            end
        else
            return nil, "result requested an unsupported field operation"
        end
        normalized.fields[#normalized.fields + 1] = {name = field.source, render = field.render,}
    end

    local bytes = assert(planCodec.canonical(normalized))
    normalized.fingerprint = hash.sha256("nupp.derive.result.v1\0" .. bytes)

    return normalized
end

local function render(plan, value)
    local parts = {}
    for _, field in ipairs(plan.fields) do
        local shown
        if field.render.kind == "literal" then
            shown = field.render.value
        else
            shown = type(
                value[field.name]
            ) == "string" and string.format("%q", value[field.name]) or tostring(value[field.name])
        end
        parts[#parts + 1] = field.name .. " = " .. shown
    end

    return plan.name .. " { " .. table.concat(parts, ", ") .. " }"
end

local function copy(value)
    return assert(json.decode(assert(json.encode(value))))
end

local M = {}

function M.runsAnExternalProviderThroughSerializedV1Envelopes()
    local request = descriptor()
    local firstResult = invoke(request)
    local secondResult = invoke(request)
    local first, why = validate(request, firstResult)
    assert(first, why)
    local second, secondWhy = validate(request, secondResult)
    assert(second, secondWhy)
    assert(first.fingerprint == second.fingerprint, "equal external results do not canonicalize deterministically")

    local corpus = {
        {name = "world.list", arguments = "{}"},
        {name = "world.spawn", arguments = '{"components":["Position","Velocity"],"authorization":"Bearer secret"}'},
        {name = "session.inspect", arguments = '{"entity":42,"fields":["name"],"token":"private"}'},
    }
    for _, item in ipairs(corpus) do
        local output = render(first, item)
        assert(output:find(item.name, 1, true), output)
        assert(output:find("arguments = <redacted>", 1, true), output)
        assert(not output:find(item.arguments, 1, true), output)
    end
end

function M.rejectsSyntaxCompilerObjectsAndUnboundedOperations()
    local request = descriptor()
    local result = invoke(request)
    local valid, why = validate(request, result)
    assert(valid, why)

    local source = copy(result)
    source.additions[1].source = "return os.execute('anything')"
    assert(not validate(request, source), "raw source entered the semantic envelope")

    local ast = copy(result)
    ast.ast = {kind = "function"}
    assert(not validate(request, ast), "an AST entered the semantic envelope")

    local helper = copy(result)
    helper.additions[1].fields[2].render = {kind = "helper", value = "tecs.io.mcp.trace.summarizeArguments",}
    assert(not validate(request, helper), "an arbitrary helper call entered the result")

    local oversized = copy(result)
    oversized.additions[1].fields[2].render.value = string.rep("x", MAX_LITERAL_BYTES + 1)
    assert(not validate(request, oversized), "an unbounded literal entered the result")

    local mismatched = copy(result)
    mismatched.fingerprint = "different-request"
    assert(not validate(request, mismatched), "a result was accepted for another request")
end

function M.keepsThePrototypeAndDecisionExplicitlyUnstable()
    local path = HERE .. "/../plans/derives-d6-provider-decision.md"
    local file = assert(io.open(path, "rb"))
    local decision = file:read("*a")
    file:close()
    assert(decision:find("Reject a public provider ABI", 1, true), decision)
    assert(decision:find("compatibility promise", 1, true), decision)
    assert(decision:find("token, AST, or CST", 1, true), decision)
    assert(decision:find("not a security boundary", 1, true), decision)
end

function M.runsThePublicComptimeForwardingRecipeEndToEnd()
    local consumer = HERE .. "/fixtures/deriveinspect_consumer.nupp"
    local checked, checkOutput = process.capture({NUPP, "check", "--strict", consumer})
    assert(checked == 0, checkOutput)
    local ran, runOutput = process.capture({NUPP, "run", consumer})
    assert(ran == 0, runOutput)

    local localProvider = HERE .. "/fixtures/derivelocal.nupp"
    local ranLocal, localOutput = process.capture({NUPP, "run", localProvider})
    assert(ranLocal == 0, localOutput)

    local invalid = HERE .. "/fixtures/deriveinspect_invalid.nupp"
    local rejected, rejection = process.capture({NUPP, "check", invalid})
    assert(rejected ~= 0, "unsupported provider input was accepted")
    assert(rejection:find("NUPP2810", 1, true), rejection)
    assert(rejection:find("unsupported", 1, true), rejection)

    local invalidProvider = HERE .. "/fixtures/deriveinvalidprovider.nupp"
    local refused, refusal = process.capture({NUPP, "check", invalidProvider})
    assert(refused ~= 0, "invalid provider declarations were accepted")
    assert(refusal:find("NUPP2809", 1, true), refusal)

    local immutable = HERE .. "/fixtures/deriveimmutable.nupp"
    local mutated, mutation = process.capture({NUPP, "check", immutable})
    assert(mutated ~= 0, "a provider mutated its Info projection")
    assert(mutation:find("cannot be assigned through", 1, true), mutation)
end

return M
