-- Test-only historical fault injection for the bounded SIMD equivalence gate.
local M = {}
local selected = os.getenv("NUPP_SIMD_EQUIVALENCE_MUTATION")

function M.active(id)
    return selected == id
end

function M.marker(id, failureMode, detail)
    local prefix = ("SIMD_EQUIVALENCE_KILL:%s:%s"):format(id, failureMode)
    return detail and (prefix .. ": " .. detail) or prefix
end

function M.text(id, source, pattern, replacement)
    if not M.active(id) then
        return source
    end
    local changed, count = source:gsub(pattern, replacement, 1)
    assert(count == 1, "equivalence mutation fixture did not match " .. id)

    return changed
end

return M
