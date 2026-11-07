local namespace = require('nupp.runtime.standardio')
local M = {}

function M.malformedTablePathPreservesMainWrapperBehavior()
    local ok, message = pcall(namespace.open, {}, 'r')
    assert(not ok and type(message) == 'string')
    assert(message:find('nil value', 1, true), message)
end

function M.stringAndDuckPathKeepSharedOpenBehavior()
    local path = os.tmpname()
    local ok, message = pcall(function()
        local file = assert(namespace.open(path, 'wb'))
        assert(file:write('path-control'))
        assert(file:close())
        local pathlike = {
            tostring = function()
                return path
            end
        }
        file = assert(namespace.open(pathlike, 'rb'))
        assert(file:read('*a') == 'path-control')
        assert(file:close())
    end)
    os.remove(path)
    assert(ok, message)
end

return M
