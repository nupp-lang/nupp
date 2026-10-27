local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local M = {}

function M.verifiedSeedDeliveryAndExecutionRoutingRefuseInvalidInputs()
    local pipe = assert(io.popen("python3 '" .. HERE .. "/bootstrapseedtest.py' 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    assert(output:match("__exit__:0%s*$"), output)
end

return M
