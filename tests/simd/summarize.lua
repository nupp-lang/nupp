local runner = require("tests.simd.runner")
local directory = assert(arg[1])
local rows = {}
local selection = runner.json(directory .. "/selection.json")

local function optional(path)
    local ok, value = pcall(runner.read, path)
    return ok and value or "unavailable"
end

local compilerNames = {}
for line in runner.read(directory .. "/matrix.tsv"):gmatch("[^\r\n]+") do
    local compiler, tier, family, element, status, result = line:match(
        "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$"
    )
    assert(compiler, "malformed matrix row")
    local prefix = directory .. "/compiler-" .. compiler
    local version = optional(prefix .. "/version.txt"):match("[^\r\n]+") or "unavailable"
    local dialect = version:lower():find("clang", 1, true)
        and "clang"
        or (version:lower():find("gcc", 1, true) or version:find("Free Software Foundation", 1, true))
        and "gcc"
        or "unknown"
    compilerNames[dialect] = true
    local row = {
        compiler = compiler,
        command = optional(prefix .. "/command.txt"):gsub("\n$", ""),
        compilerVersion = version,
        target = optional(prefix .. "/target.txt"):gsub("\n$", ""),
        dialect = dialect,
        tier = tier,
        family = family,
        element = element,
        status = status,
        evidence = result
    }
    if status == "executed" then
        local ok, value = pcall(runner.json, result)
        if ok then
            row.execution = value
        else
            row.status, row.reason = "failed", tostring(value)
        end
    elseif status == "not-executed" then
        row.reason = "Host CPU does not advertise the required feature tier"
    end
    rows[#rows + 1] = row
end
local report = require("tests.simd.native-summary").summarize(selection, rows)
report.runtimeBoundaries = runner.json(runner.root() .. "/tests/simd/runtime-boundaries.json")
report.revision = runner.read(directory .. "/revision.txt"):gsub("\n$", "")
report.host = runner.read(directory .. "/host.txt"):gsub("\n$", "")
report.compilerDialects = compilerNames
report.cpu = runner.read(directory .. "/cpu.txt")
report.vm = runner.read(directory .. "/vm.txt")
report.scope = "The frozen requested native selection, verified against completed native and scalar-C calls; unavailable tiers remain incomplete."
local executed, unavailable, failures = report.executed, report.unavailable, report.failed
runner.writeJson(directory .. "/summary.json", report)
print(
    "SIMD matrix: "
    .. executed
    .. " executed, "
    .. unavailable
    .. " unavailable, "
    .. failures
    .. " failed; complete="
    .. tostring(
        report.requested_native_matrix_complete
    )
)

if failures > 0 or (executed == 0 and unavailable == 0) then
    os.exit(1)
end
