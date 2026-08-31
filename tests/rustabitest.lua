local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local M = {}

function M.publicHeaderLinksAndRunsAgainstTheSelectedCdylib()
    local pipe = assert(io.popen("'" .. ROOT:gsub("'", "'\\''") .. "/scripts/test-rust-abi' 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))
    assert(status == 0, output)
end

return M
