local core = require("nupp.serde.value")
local codec = require("nupp.serde.json")
local root, visible, skipped, redacted = {name = "Root"}, {name = "visible"}, {name = "skipped"}, {name = "redacted"}
local gets, describes, constructs = 0, 0, 0

local function scalar(member, kind)
    return {member = member, kind = kind, nullable = false, canRead = true, children = {}}
end

local function child(member, kind, required, default)
    return {
        member = member,
        required = required,
        hasDefault = default,
        describe = function()
            describes = describes + 1
            return scalar(member, kind)
        end
    }
end

local description = scalar(root, "structure")
description.children = {
    child(visible, "string", true, false),
    child(skipped, "opaque", true, true),
    child(redacted, "opaque", true, true)
}
local members = {
    apply = function(_, value, writer)
        for _, member in ipairs({visible, skipped, redacted}) do
            if writer:include(member) then
                gets = gets + 1
                writer:writeString(member, value[member.name])
            end
        end
    end
}
local adapter = {
    describe = function()
        return description
    end,
    write = function(_, value, writer)
        writer:writeStruct(root, value, members)
    end,
    read = function(_, reader)
        local state = {}
        reader:readStruct(
            root,
            state,
            {
                apply = function(_, state, member, input)
                    assert(member == visible)
                    state.visible = input:readString(member)
                end
            },
            {
                apply = function()
                    error("unknown member", 0)
                end
            }
        )
        assert(state.visible, "missing required member")
        constructs = constructs + 1
        state.skipped, state.redacted = function()
            return "default"
        end, function()
            return "default"
        end

        return state
    end,
}
local binding = setmetatable({adapter = adapter}, core.Bound)

local function profile(traverseAll)
    return {
        policy = function()
            return {
                name = function(_, member)
                    return member.name
                end,
                select = function(_, member)
                    return not traverseAll and (member == skipped and "omit" or member == redacted and "redact")
                    or "traverse"
                end,
            }
        end
    }
end

local policy = profile(false)
local value = {
    visible = "ok",
    skipped = function()
        error("never read")
    end,
    redacted = function()
        error("never read")
    end
}
assert(codec.encode(binding, value, policy) == '{"visible":"ok","redacted":"[redacted]"}')
assert(gets == 1 and describes == 1)
local decoded = codec.decode(binding, '{"visible":"ok","skipped":{"unknown":[null]},"redacted":42}', policy)
assert(decoded.visible == "ok" and decoded.skipped() == "default" and constructs == 1)
assert(describes == 2)
assert(not pcall(codec.decode, binding, '{"visible":"ok","skipped":[1,]}', policy))
assert(constructs == 1)
local before = gets
assert(not pcall(codec.encode, binding, value, profile(true)))
assert(gets == before, "unsupported selected children must fail before reading values")
print("selection skips opaque child preparation and access, validates ignored syntax, and constructs defaults")
