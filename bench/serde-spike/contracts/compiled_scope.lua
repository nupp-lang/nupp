local fixture = require("contract.compiledfixture")
local compiled = require("nupp.serde.jsoncompiled")
local fused = require("nupp.codec.json.aot")
local json = require("nupp.serde.json")
local operations = fixture.inspect(fixture.recordBinding)
assert(compiled.supports(operations.adapter, operations.plan))
local nullable = fixture.inspect(fixture.nullableBinding)
assert(not compiled.supports(nullable.adapter, nullable.plan))
local fixed = fixture.inspect(fixture.fixedBinding)
assert(compiled.supports(fixed.adapter, fixed.plan))
local decoder = assert(compiled.select(operations.adapter, operations.plan, fused))
for _, source in ipairs({
    '{"name":"one","child":{"value":"nested"}}',
    '{"child":{"value":"nested"},"enabled":false,"name":"two"}',
}) do
    local native, visitor = decoder:decode(source), fixture.visitor(source)
    assert(native.name == visitor.name and native.enabled == visitor.enabled)
    assert(native.child.value == visitor.child.value)
    assert(getmetatable(native) == fixture.Record and getmetatable(native.child) == fixture.Child)
end
for _, source in ipairs({
    '{"name":"one","child":{"value":"nested"},"name":"duplicate"}',
    '{"name":"one","child":{"value":false}}',
    '{"name":"one","child":{}}',
    '{"name":"one","child":{"value":"nested"},"enabled":null}',
    '{"name":"one","child":{"value":"nested"}} trailing',
    '{"name":"one","child":{"value":"nested"},"unknown":1e9999}',
}) do
    assert(not pcall(decoder.decode, decoder, source), source)
    assert(not pcall(fixture.visitor, source), source)
end
local dynamic = fixture.inspect(fixture.indexedBinding, fixture.indexedPolicy)
assert(compiled.supports(dynamic.adapter, dynamic.plan))
local dynamicDecoder = assert(compiled.select(dynamic.adapter, dynamic.plan, fused))
local value = dynamicDecoder:decode('{"name":"indexed"}')
assert(value:get(fixture.slot) == "indexed")
assert(json.encode(fixture.indexedBinding, value, fixture.indexedPolicy) == '{"name":"indexed"}')
print("checked native recipes preserve nested records and indexed values")

local fixed = fixture.inspect(fixture.fixedBinding)
local integers = assert(compiled.select(fixed.adapter, fixed.plan, fused))
for _, token in ipairs({"0", "1", "4294967295"}) do
    assert(integers:decode('{"value":' .. token .. '}').value == tonumber(token))
end
for _, token in ipairs({"1.0", "1e0", "-0", "-1", "4294967296", "1e9999"}) do
    assert(not pcall(integers.decode, integers, '{"value":' .. token .. '}'), token)
end

-- Diagnostics inspect syntax without repeating user construction.
local validated = fixture.inspect(fixture.validatedBinding)
local checked = assert(compiled.select(validated.adapter, validated.plan, fused))
local before = fixture.constructorCalls()
assert(checked:decode('{"text":"ok"}').text == "ok")
assert(fixture.constructorCalls() == before + 1)
assert(not pcall(checked.decode, checked, '{"text":"bad"}'))
assert(fixture.constructorCalls() == before + 2)
assert(not pcall(checked.decode, checked, '{"text":"ok"} trailing'))
assert(fixture.constructorCalls() == before + 2)
local _, nativeError = pcall(decoder.decode, decoder, '{"name":"one","child":{"value":false}}')
local _, visitorError = pcall(fixture.visitor, '{"name":"one","child":{"value":false}}')
assert(nativeError.path == visitorError.path and nativeError.code == visitorError.code)
assert(nativeError.byte == visitorError.byte)
assert(not decoder:accepts(string.rep(" ", 1000001)))
local attempts = 0
local wrapped = {
    describe = function()
        return operations.adapter:describe("read")
    end,
    read = function()
        attempts = attempts + 1;
        error("custom read")
    end
}
assert(not compiled.supports(wrapped, operations.plan))
assert(
    compiled.select(wrapped, operations.plan, {
        compileSerde = function()
            attempts = attempts + 1;
            error("unexpected compile")
        end,
        decodeSerde = function()
            attempts = attempts + 1;
            error("unexpected decode")
        end,
    }) == nil
)
assert(attempts == 0)

local nested = fixture.inspect(fixture.nestedValidatedBinding)
local nestedDecoder = assert(compiled.select(nested.adapter, nested.plan, fused))
local priorCalls = fixture.constructorCalls()
local ok, failure = pcall(nestedDecoder.decode, nestedDecoder, '{"child":{"text":"object-error"}}')
assert(not ok and failure.cause == fixture.constructorFailure, tostring(failure))
assert(failure.path == '$["child"]' and fixture.constructorCalls() == priorCalls + 1)

local syntax = require("nupp.serde.jsonsyntax")
local readers = require("nupp.serde.jsonreader")
local declarations = require("nupp.serde.declaration")
local collections = fixture.inspect(fixture.collectionsBinding)
local sequence = assert(compiled.select(collections.adapter, collections.plan, fused))
local policy = declarations.policy():policy(collections.adapter:describe("read").member)

local function collectionVisitor(bytes)
    local cursor = syntax.reader(bytes)
    local reader = readers.input(cursor, policy, collections.plan, nil)
    local ok, value = pcall(collections.adapter.read, collections.adapter, reader)
    reader:expire()
    if not ok then
        error(value, 0)
    end
    cursor:finish()

    return value
end

local input = '{"rows":[{"value":1},{"value":4294967295}],"labels":{"a":"one"},"pair":[2,"two"]}'
local value = sequence:decode(input)
assert(getmetatable(value) == fixture.Collections and getmetatable(value.rows[1]) == fixture.Fixed)
assert(value.rows[2].value == 4294967295 and value.labels.a == "one" and value.pair[2] == "two")
assert(
    json.encode(fixture.collectionsBinding, value) == json.encode(fixture.collectionsBinding, collectionVisitor(input))
)
for _, invalid in ipairs({
    input:gsub('4294967295', '4294967296'),
    input:gsub('"a":"one"', '"a":null'),
    input:gsub('%[2,"two"%]', '[2]'),
    input:gsub('%[2,"two"%]', '[2,"two",3]'),
    (input:gsub('{"value":1}', '{}', 1)),
}) do
    local nativeOk, failure = pcall(sequence.decode, sequence, invalid)
    local visitorOk = pcall(collectionVisitor, invalid)
    assert(not nativeOk and not visitorOk, invalid)
    assert(failure.path ~= nil and failure.byte ~= nil)
end

-- Cached writers retain the same dynamic paths and transactional output.
local text = require("nupp.text")
local buffer = text.newBuffer()
buffer:put("prefix:")
value.rows[2].value = -1
local ok, failure = pcall(json.write, fixture.collectionsBinding, value, buffer)
assert(not ok and failure.path == '$["rows"][2]["value"]', tostring(failure))
assert(buffer:tostring() == "prefix:")
value.rows[2].value = 2
value.labels.a = false
ok, failure = pcall(json.write, fixture.collectionsBinding, value, buffer)
assert(not ok and failure.path == '$["labels"]["a"]', tostring(failure))
assert(buffer:tostring() == "prefix:")
local many = setmetatable({items = {}}, fixture.Numbers)
for index = 1, 1000000 do
    many.items[index] = index
end
ok, failure = pcall(json.write, fixture.numbersBinding, many, buffer)
assert(not ok and failure.code == "limit", tostring(failure))
assert(failure.path:find('$["items"][', 1, true) == 1, failure.path)
assert(buffer:tostring() == "prefix:")

-- Buffer input reaches the provider without another facade copy. The current
-- native host bridge materializes one input string; a future borrowing bridge
-- may eliminate that copy without changing this contract.
local inputBuffer = text.newBuffer()
inputBuffer:put('{"name":"buffer","child":{"value":"nested"}}')
assert(decoder:acceptsBuffer(inputBuffer))
local methods = debug.getmetatable(inputBuffer).__index
local originalToString, copies = methods.tostring, 0
methods.tostring = function(self, ...)
    if self == inputBuffer then
        copies = copies + 1
    end
    return originalToString(self, ...)
end
local accepted, result = pcall(decoder.decodeBuffer, decoder, inputBuffer)
methods.tostring = originalToString
assert(accepted, tostring(result))
assert(result.name == "buffer" and copies <= 1, tostring(result.name) .. ": full-input copies=" .. tostring(copies))
assert(originalToString(inputBuffer) == '{"name":"buffer","child":{"value":"nested"}}')
inputBuffer:set('{"name":"buffer","child":{"value":false}}')
local acceptedBuffer, bufferError = pcall(decoder.decodeBuffer, decoder, inputBuffer)
local acceptedString, stringError = pcall(decoder.decode, decoder, inputBuffer:tostring())
assert(not acceptedBuffer and not acceptedString)
assert(bufferError.path == stringError.path and bufferError.byte == stringError.byte)
-- The public facade also works when its selected provider uses a string route.
inputBuffer:set('{"name":"facade","child":{"value":"retained"}}')
local facade = json.codec()
assert(facade:decodeBuffer(fixture.recordBinding, inputBuffer).child.value == "retained")
assert(json.decodeBuffer(fixture.recordBinding, inputBuffer).name == "facade")
