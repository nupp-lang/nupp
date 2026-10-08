local test = require("nupp.test")

local M = {}

function M.clean(result, label)
    if type(result) == "string" then
        test.equal(result, "", label or "expected a clean check")
        return
    end
    local diagnostics = result
    local first = diagnostics[1]
    local detail = label or "expected a clean check"
    if first ~= nil then
        detail = detail .. ": " .. tostring(first.msg or first.message or first)
    end
    test.equal(#diagnostics, 0, detail)
end

function M.check(checker, labeler)
    return function(source, options)
        local result = checker(source, options)
        local label = labeler and labeler(source) or nil
        M.clean(result, label)
    end
end

return M
