-- CLI smoke for open-binding contracts.
local call = require("helpers.serdecontract").call
local json = require("testjson")
local M = {}

function M.externalMembersEraseBehindACheckedBinding()
    local status, output = call({
        "check",
        "--json",
        "erasure.nupp",
        "src/contract/dispatch.nupp",
        "src/contract/render.nupp",
        "src/example/model.nupp",
        "src/example/other.nupp"
    })
    assert(status == 0, output)
    local checked = json.decode(output)
    assert(checked.ok and #checked.diagnostics == 0, output)
    status, output = call({"run", "erasure.nupp"})
    assert(status == 0, output)
end

return M
