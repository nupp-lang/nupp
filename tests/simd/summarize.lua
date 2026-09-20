local runner = require("tests.simd.runner")
local directory = assert(arg[1])
local rows = {}
local complete, passed = true, true
local executed, unavailable, failures = 0, 0, 0
local compilerNames = {}
for line in runner.read(directory .. "/matrix.tsv"):gmatch("[^\r\n]+") do
    local compiler, tier, family, element, status, result = line:match(
        "^([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t([^\t]+)\t(.+)$"
    )
    assert(compiler, "malformed matrix row")
    local prefix = directory .. "/compiler-" .. compiler
    local version = runner.read(prefix .. "/version.txt"):match("[^\r\n]+")
    local dialect = version:lower():find("clang", 1, true)
        and "clang"
        or (version:lower():find("gcc", 1, true) or version:find("Free Software Foundation", 1, true))
        and "gcc"
        or "unknown"
    compilerNames[dialect] = true
    local row = {
        compiler = compiler,
        command = runner.read(prefix .. "/command.txt"):gsub("\n$", ""),
        compilerVersion = version,
        target = runner.read(prefix .. "/target.txt"):gsub("\n$", ""),
        dialect = dialect,
        tier = tier,
        family = family,
        element = element,
        status = status,
        evidence = result
    }
    if status == "executed" then
        row.execution = runner.json(result)
        assert(row.execution.ok and row.execution.tier == tier and row.execution.nativeCalls > 0)
        executed = executed + 1
    elseif status == "not-executed" then
        complete, unavailable = false, unavailable + 1
        row.reason = "Host CPU does not advertise the required feature tier"
    else
        complete, passed, failures = false, false, failures + 1
    end
    rows[#rows + 1] = row
end
local report = {
    schemaVersion = 1,
    runtimeBoundaries = runner.json(runner.root() .. "/tests/simd/runtime-boundaries.json"),
    revision = runner.read(directory .. "/revision.txt"):gsub("\n$", ""),
    host = runner.read(directory .. "/host.txt"):gsub("\n$", ""),
    rows = rows,
    executed = executed,
    unavailable = unavailable,
    failed = failures,
    available_execution_pass = passed and executed > 0,
    requested_native_matrix_complete = complete and executed > 0,
    compilerDialects = compilerNames,
    outcome = failures > 0 and "failed" or executed > 0 and "executed" or "not-executed",
    lanes = runner.read(directory .. "/lanes.txt"):gsub("\n$", ""),
    cpu = runner.read(directory .. "/cpu.txt"),
    vm = runner.read(directory .. "/vm.txt"),
    scope = "Native shared SIMD corpora; unavailable tiers leave requested_native_matrix_complete=false. Wasm is reported separately."
}
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
