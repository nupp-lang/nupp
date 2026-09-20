-- The full species matrix is driven by tests/simd's native/Wasm runner in CI.
-- Local focused validation keeps the register, odd aggregate and widest tails.
local M = {}

function M.horizontalAndLoopContractsReachNativeCode()
    local generated = require("tests.simd.reducers").generate{
        lanes = {2, 3, 7, 8, 16, 31, 32, 63, 64, "preferred"},
    }
    local report = require("tests.simd.runner").native(generated)
    assert(report.ok and report.cases > 0 and report.nativeCalls > 0)
end

return M
