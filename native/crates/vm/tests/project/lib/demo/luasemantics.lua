local M = {}
function M.run()
    local function identity(value)
        return value
    end

    assert(identity{answer = 42}.answer == 42)
    assert(identity"text" == "text")
    local object = {}
    function object:identity(value)
        assert(self == object)
        return value
    end

    assert(object:identity({answer = 42}).answer == 42)
    assert(object:identity("text") == "text")
    local ok, handled = xpcall(
        function()
            error("original")
        end,
        function(problem)
            assert(problem == "original")
            return "handled"
        end
    )
    assert(not ok and handled == "handled")
    local success, first, last = xpcall(
        function()
            return 42, "last"
        end,
        function()
            error("unexpected handler")
        end
    )
    assert(success and first == 42 and last == "last")
    local failed, reason = xpcall(
        function()
            error("body")
        end,
        function()
            error("handler")
        end
    )
    assert(not failed and reason == "error in error handling")
    local fileType = assert(io.type)
    assert(fileType(io.stdout) == "file" and fileType({}) == nil)
    local numeric = 3
    numeric = string.match("done", "^[0-9]+")
    assert(numeric == nil and not numeric)

    local function empty()
    end

    local reused = 42
    reused = empty()
    assert(reused == nil)
    local unknown = missingProbeGlobal
    assert(unknown == nil)

    local function invokeOptional(value)
        return math.cos(value)
    end

    local dynamicMath = _G["math"]
    local originalCos = dynamicMath.cos
    dynamicMath.cos = nil
    assert(_G["io"]["missingProbe"] == nil and math.cos == nil)
    dynamicMath.cos = function(value)
        return value + 1
    end
    assert(invokeOptional(41) == 42)
    dynamicMath.cos = originalCos

    local keys = {}
    for key in pairs({[false] = "no", [true] = "yes"}) do
        keys[key] = true
    end
    assert(keys[false] and keys[true])
    local rounds = 0

    local function step()
        rounds = rounds + 1
        if rounds == 1 then
            return false, 42
        elseif rounds == 2 then
            return true
        end
    end

    local seen = 0
    for key, value in step do
        seen = seen + 1
        assert(key == false and value == 42 or key == true and value == nil)
    end
    assert(seen == 2)

    local object = {a_field_name_longer_than_the_short_string_interning_threshold = 42}
    local name = "a_field_name_longer_than_" .. "the_short_string_interning_threshold"
    assert(object[name] == 42)

    return 42
end

return M
