-- The page-side browser host, which is JavaScript, under Node's test runner.
--
-- `tests/integration/browser/wasm-aot/runtime.test.mjs` exercises
-- `runtime/wasm/app-runtime.mjs` and `worker-pool.mjs`: effect frames and their wake
-- modes, leases, the WebGPU checks, application budgets and the worker pool's stale and
-- malformed replies. It needs nothing but Node, and without a suite nothing ran it.
--
-- `tests/integration/simd/*.test.mjs` are the Wasm SIMD matrix's own helpers: how it
-- finds an entry's symbol, how it aggregates shards and judges evidence. The matrix
-- runs nightly, so a helper that drifts from the compiler shows up there a day late and
-- as every shard failing at once.

local check = require("assert")

local M = {}

local HERE = require("helpers.paths").tests

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
        check.suite.skip("node is not installed")
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
    check(passed ~= nil and failed ~= nil, "node printed no test summary:\n" .. output)
    check.eq(failed, 0, label .. " failed:\n" .. output)
    check(passed > 0, label .. " ran no test")
    check(exited, "node exited unsuccessfully:\n" .. output)
end

function M.thePageHostPassesItsNodeSuite()
    passesNodeSuite("the page host's Node suite", {
        "integration/browser/wasm-aot/runtime.test.mjs",
        "integration/browser/wasm-aot/channel.test.mjs",
        "integration/browser/wasm-aot/channel-host.test.mjs",
    })
end

function M.theWasmSimdHelpersPassTheirNodeSuites()
    passesNodeSuite("the Wasm SIMD helpers' Node suites", {
        "integration/simd/aggregate-wasm.test.mjs",
        "integration/simd/native-shards.test.mjs",
        "integration/simd/wasm-algorithm-evidence.test.mjs",
        "integration/simd/wasm-entry-name.test.mjs",
    })
end

--- The matrix finds an entry by the symbol tail the compiler would give its name,
--- and computes that tail itself; ask the compiler rather than trust the copy.
function M.theWasmEntryNameAgreesWithTheCompiler()
    requireNode()
    local scalar = require("nupp.compiler.aot.scalar")
    local names = {
        "sum",
        "wrappingSum",
        "x9y",
        "fields_2",
        "indexed_17",
        "masked_i32_Min",
        "masked_i32_wrappingSum",
        "parseJSONValue",
        "HTTPServer",
        "a-b",
        "\195\169",
    }
    local script = "const {pathToFileURL} = await import('node:url');"
        .. " const {loweredEntryName} = await import(pathToFileURL(process.argv[1]).href);"
        .. " for (const name of process.argv.slice(2)) console.log(loweredEntryName(name));"
    local quoted = {shellQuote(HERE .. "/integration/simd/wasm-entry-name.mjs")}
    for _, name in ipairs(names) do
        quoted[#quoted + 1] = shellQuote(name)
    end
    local output, exited = runNode(
        "node --input-type=module -e " .. shellQuote(script) .. " " .. table.concat(quoted, " ")
    )
    check(exited, "node exited unsuccessfully:\n" .. output)
    local index = 0
    for line in output:gmatch("[^\n]+") do
        index = index + 1
        local name = names[index]
        check.eq(line, scalar.privateSymbol(name):sub(#"ks_" + 1), "the symbol tail of " .. tostring(name))
    end
    check.eq(index, #names, "node answered a different number of names:\n" .. output)
end

return M
