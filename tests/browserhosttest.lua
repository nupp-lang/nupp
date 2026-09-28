-- The page-side browser host, which is JavaScript, under Node's test runner.
--
-- `tests/wasm-aot/runtime.test.mjs` exercises `runtime/wasm/app-runtime.mjs` and
-- `worker-pool.mjs`: effect frames and their wake modes, leases, the WebGPU checks,
-- application budgets and the worker pool's stale and malformed replies. It needs
-- nothing but Node, and without a suite nothing ran it.

local check = require("assert")

local M = {}

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function shellQuote(text)
    return "'" .. text:gsub("'", "'\\''") .. "'"
end

function M.thePageHostPassesItsNodeSuite()
    local probe = io.popen("node --version 2>/dev/null")
    local version = probe and probe:read("*a") or ""
    if probe then
        probe:close()
    end
    if not version:match("^v%d+") then
        check.skip("node is not installed")
    end
    local command = "node --test --test-reporter=tap " .. shellQuote(HERE .. "/wasm-aot/runtime.test.mjs") .. " 2>&1"
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    local closed, _, status = pipe:close()
    local passed = tonumber(output:match("\n# pass (%d+)"))
    local failed = tonumber(output:match("\n# fail (%d+)"))
    check.assert(passed ~= nil and failed ~= nil, "node printed no test summary:\n" .. output)
    check.equal(failed, 0, "the page host's Node suite failed:\n" .. output)
    check.assert(passed > 0, "the page host's Node suite ran no test")
    check.assert(closed == true or status == 0, "node exited unsuccessfully:\n" .. output)
end

return M
