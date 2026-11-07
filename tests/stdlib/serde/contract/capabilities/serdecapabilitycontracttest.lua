-- A cold capability lookup is the obligation, so use a fresh process.
local process = require("nupp.compiler.process")
local root = require("helpers.paths").root
local M = {}

function M.declarationBindingsCheckCarrierCapabilitiesBeforeReading()
    local status, output = process.capture({root .. "/bin/nupp", "run", "declaration_capabilities.nupp"}, {
        cwd = root .. "/bench/serde-spike/contracts"
    })
    assert(status == 0, output)
end

return M
