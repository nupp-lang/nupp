-- Synthetic cache/verification contracts only. Actual upstream header/library
-- ABI and crypto vectors run in the five-target c-libraries workflow.
local M = {}
function M.sharedProvisionerRejectsCorruptionAndReusesVerifiedOutputs()
    local status = os.execute("node --test tests/tools/toolchain/clibraries.test.mjs")
    assert(status == 0, "C library provisioning contracts failed")
end

return M
