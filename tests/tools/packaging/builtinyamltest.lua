-- The yaml builtin's closure (`builtinclosure.lua` over the registered entry):
-- a program that requires serde.yaml carries its modules, nupp_yaml and the
-- libyaml notice; programs that do not -- one printing, one using serde.json,
-- whose serde does not require serde.yaml -- carry no YAML module, reference,
-- library, notice or yaml_ symbol; `--without yaml` refuses the chain that
-- reaches it; and a build for the browser, which cannot provide it, is
-- refused naming the host.
--
-- Each build is a core binary, minutes apiece. Set NUPP_BUILTIN_CLOSURE_RECORD
-- to a path prefix to keep each run's package sizes.
local closure = require("tools.packaging.builtinclosure")

local FIXTURES = require("helpers.paths").absoluteTests .. "/tools/packaging/fixtures"

local M = {}

local CHAIN = {"src/main.nupp", "src/app/config.nupp"}

local function prove(hello, label)
    local record = os.getenv("NUPP_BUILTIN_CLOSURE_RECORD")
    local result = closure.run({
        name = "yaml",
        hello = hello,
        uses = FIXTURES .. "/builtinyaml/uses",
        reaches = {"serde.yaml", "serde.yaml.internal.reader", "serde.yaml.internal.writer"},
        chain = CHAIN,
        record = record and record .. "-" .. label .. ".json" or nil,
    })
    assert(#result.problems == 0, "the closure harness found:\n  " .. table.concat(result.problems, "\n  "))
    -- A program that only prints is the smaller; one using serde.json may
    -- carry more than the YAML program does.
    if label == "hello" then
        assert(result.sizes.uses > result.sizes.hello, "uses carries more than hello")
    end
    io.stderr:write(
        ("builtin closure %s: hello %d bytes, uses %d bytes, yaml %d bytes\n"):format(
            label,
            result.sizes.hello,
            result.sizes.uses,
            result.sizes.difference
        )
    )
end

function M.yamlIsCarriedOnlyWhereItIsReached()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    prove(FIXTURES .. "/builtinclosure/hello", "hello")
end

function M.aJsonProgramCarriesNoYaml()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    prove(FIXTURES .. "/builtinyaml/jsonhello", "json")
end

function M.aBrowserHostCannotProvideIt()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    local directory = os.tmpname()
    os.remove(directory)
    assert(os.execute("cp -R '" .. FIXTURES .. "/builtinyaml/uses' '" .. directory .. "'"))
    local report, built = closure.build(directory, "--host browser", nil)
    assert(not built, "a browser build reaching serde.yaml was refused")
    -- The checker refuses the C binding the browser has no host for before
    -- the builtin check is reached; either way the refusal names the host.
    local named = false
    for _, diagnostic in ipairs(report.diagnostics or {}) do
        if (diagnostic.code == "NUPP0006" or diagnostic.code == "NUPP3006")
            and diagnostic.message:find("browser", 1, true)
        then
            named = true
        end
    end
    assert(named, require("testjson").encode(report.diagnostics or {}))
    os.execute("rm -rf '" .. directory .. "'")
end

return M
