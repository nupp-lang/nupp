local xml = require("example.xmlcodec")
local binary = require("example.binarycodec")
local binarySyntax = require("example.binary")
local root = {name = "root", index = 1}
local member = {name = "value", index = 2}
local description = {
    member = root,
    kind = "structure",
    nullable = false,
    canRead = true,
    children = {
        {
            member = member,
            required = true,
            hasDefault = false,
            describe = function()
                return {member = member, kind = "string", nullable = false, canRead = true, children = {}}
            end
        }
    },
}

local function binding(adapter)
    return {
        accept = function(_, consumer, state)
            return consumer:apply(adapter, state)
        end
    }
end

local variants = {
    {
        codec = xml.codec({
            field = function(_, m)
                return {namespaceUri = "", localName = m.name, role = "element"}
            end,
            flattened = function()
                return false
            end,
        }),
        known = "<root><value>x</value></root>",
        unknown = "<root><future>x</future></root>"
    },
    {
        codec = binary.codec({
            number = function(_, m)
                return m.index
            end
        }),
        known = binarySyntax.encode({
            {field = {number = 2, wire = 1}, bytes = "x"}
        }),
        unknown = binarySyntax.encode({
            {field = {number = 99, wire = 255}, bytes = "x"}
        })
    },
}
for _, variant in ipairs(variants) do
    for _, unknown in ipairs({false, true}) do
        for _, mode in ipairs({"consume", "under", "over", "raise"}) do
            local retained, retainedRoot
            local consumer = {
                apply = function(_, state, selected, reader)
                    retained = reader
                    if mode == "under" then
                        return
                    end
                    if mode == "raise" then
                        error("consumer failed", 0)
                    end
                    if unknown then
                        reader:skipValue()
                    else
                        assert(reader:readString(member) == "x")
                    end
                    if mode == "over" then
                        if unknown then
                            reader:skipValue()
                        else
                            reader:readString(member)
                        end
                    end
                end
            }
            local selected = binding({
                describe = function()
                    return description
                end,
                read = function(_, reader)
                    retainedRoot = reader
                    reader:readStruct(root, {}, consumer, consumer)
                    return true
                end,
            })
            local ok, problem = pcall(
                variant.codec.decode,
                variant.codec,
                selected,
                unknown and variant.unknown or variant.known
            )
            assert(ok == (mode == "consume"), tostring(problem))
            assert(retained ~= nil)
            local alive, expired = pcall(function()
                if unknown then
                    retained:skipValue()
                else
                    retained:isNull()
                end
            end)
            assert(not alive and tostring(expired):find("expired", 1, true), tostring(expired))
            assert(not pcall(retainedRoot.isNull, retainedRoot))
        end
    end
    local calls = 0
    local broken = binding({
        describe = function()
            calls = calls + 1;
            error("unsupported selection", 0)
        end
    })
    for i = 1, 2 do
        local ok, failure = pcall(variant.codec.decode, variant.codec, broken, "malformed input")
        assert(not ok and tostring(failure):find("unsupported selection", 1, true), tostring(failure))
    end
    assert(calls == 1, "failed schema extension was initialized again")
end
