local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local M = {}

local function quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.nativePinMovesVerifyPublicationAndPreservePinsOnFailure()
    local command = "bash " .. quote(
        HERE .. "/fixtures/stage0/advance.sh"
    ) .. " " .. quote(HERE .. "/../scripts/advance-stage0")
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    assert(output:match("__exit__:0%s*$"), output)
    assert(output:find("PASS preparation", 1, true), output)
    assert(output:find("PASS runtime preservation", 1, true), output)
end

return M
