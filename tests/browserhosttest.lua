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

local function requireNode()
    local probe = io.popen("node --version 2>/dev/null")
    local version = probe and probe:read("*a") or ""
    if probe then
        probe:close()
    end
    if not version:match("^v%d+") then
        check.skip("node is not installed")
    end
end

local function runNode(command)
    local pipe = assert(io.popen(command .. " 2>&1"))
    local output = pipe:read("*a")
    local closed, _, status = pipe:close()
    return output, closed == true or status == 0
end

local function passesNodeSuite(label, files)
    requireNode()
    local quoted = {}
    for index, file in ipairs(files) do
        quoted[index] = shellQuote(HERE .. "/" .. file)
    end
    local output, exited = runNode("node --test --test-reporter=tap " .. table.concat(quoted, " "))
    local passed = tonumber(output:match("\n# pass (%d+)"))
    local failed = tonumber(output:match("\n# fail (%d+)"))
    check.assert(passed ~= nil and failed ~= nil, "node printed no test summary:\n" .. output)
    check.equal(failed, 0, label .. " failed:\n" .. output)
    check.assert(passed > 0, label .. " ran no test")
    check.assert(exited, "node exited unsuccessfully:\n" .. output)
end

function M.thePageHostPassesItsNodeSuite()
    passesNodeSuite("the page host's Node suite", {"wasm-aot/runtime.test.mjs"})
end

return M
