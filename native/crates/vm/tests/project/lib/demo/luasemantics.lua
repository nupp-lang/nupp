local M = {}
function M.run()
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
    assert(io.popen == nil and math.cos == nil)
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
