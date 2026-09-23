-- Executable SIMD coverage obligations and migration adapters.
--
-- New harness reports carry `coverage.witness` facts. During migration, the
-- native and Wasm matrix summaries are translated into the same witness shape
-- after their completed-call evidence has been checked.
local M = {}

local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local directory = assert(source:match("^(.*)/[^/]+$"))
local root = assert(directory:match("^(.*)/tests/simd$"))
local decode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/decoder.lua"))()()
local encode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/encoder.lua"))()()

local function read(path)
    local file, problem = io.open(path, "rb")
    assert(file, ("cannot read %s: %s"):format(path, tostring(problem)))
    local text = file:read("*a") or ""
    file:close()

    return text
end

local function json(path)
    local ok, value = pcall(decode, read(path))
    assert(ok and type(value) == "table", path .. " is not valid JSON: " .. tostring(value))

    return value
end

local function sortedKeys(value)
    local keys = {}
    for key in pairs(value or {}) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    return keys
end

local function scalar(value)
    local kind = type(value)
    assert(kind == "string" or kind == "number" or kind == "boolean", "coverage dimensions must be scalar")

    return kind .. ":" .. tostring(value)
end

local function dimensionKey(obligation, dimensions, names)
    local parts = {obligation}
    for _, name in ipairs(names or sortedKeys(dimensions)) do
        assert(dimensions[name] ~= nil, "missing coverage dimension " .. name)
        parts[#parts + 1] = name .. "=" .. scalar(dimensions[name])
    end

    return table.concat(parts, "\0")
end

local function domainValues(manifest, name)
    local domain = assert(manifest.domains[name], "unknown coverage domain " .. tostring(name))
    if domain.integerRange then
        local values = {}
        for value = domain.integerRange[1], domain.integerRange[2] do
            values[#values + 1] = value
        end
        for _, value in ipairs(domain.include or {}) do
            values[#values + 1] = value
        end

        return values
    end

    return domain
end

local function merge(left, right)
    local result = {}
    for key, value in pairs(left or {}) do
        result[key] = value
    end
    for key, value in pairs(right or {}) do
        result[key] = value
    end

    return result
end

local function expandRequirement(manifest, requirement, ledger)
    local hasExpansion = next(requirement.expand or {}) ~= nil
    local combinations = hasExpansion and {merge(requirement.fixed)} or {}
    local names = sortedKeys(requirement.fixed)
    for _, dimension in ipairs(sortedKeys(requirement.expand)) do
        names[#names + 1] = dimension
        local expanded = {}
        for _, combination in ipairs(combinations) do
            for _, value in ipairs(domainValues(manifest, requirement.expand[dimension])) do
                expanded[#expanded + 1] = merge(combination, {[dimension] = value})
            end
        end
        combinations = expanded
    end
    for _, dimensions in ipairs(requirement.cases or {}) do
        local combination = merge(requirement.fixed, dimensions)
        combinations[#combinations + 1] = combination
        for name in pairs(dimensions) do
            local found = false
            for _, existing in ipairs(names) do
                found = found or existing == name
            end
            if not found then
                names[#names + 1] = name
            end
        end
    end
    if not hasExpansion and #(requirement.cases or {}) == 0 and not requirement.ledger then
        combinations = {merge(requirement.fixed)}
    end
    if requirement.ledger then
        assert(ledger and #ledger.defects == 13, "the historical defect ledger must contain exactly thirteen entries")
        combinations = {}
        names = {"defect"}
        for _, defect in ipairs(ledger.defects) do
            combinations[#combinations + 1] = {defect = defect.id}
        end
    end
    assert(#combinations > 0, "coverage requirement expands to nothing: " .. requirement.id)
    table.sort(names)

    return combinations, names
end

local FIXED_DEFECTS = {
    "pairwise-finalization",
    "signed-zero",
    "shift-masking",
    "narrow-scalar-mapping",
    "lane-bounds",
    "mixed-width-definitions",
    "symbol-collisions",
    "wasm-stack-transport",
    "wasm-wide-transport",
    "gcc-sra",
    "neon-field-pairs",
    "avx2-windows",
    "target-vector-ceilings",
}

local function validateLedger(ledger)
    assert(ledger.schemaVersion == 1, "unsupported defect ledger schema")
    assert(type(ledger.defects) == "table" and #ledger.defects == 13, "defect ledger must contain thirteen entries")
    local seenDefects, seenWitnesses = {}, {}
    for index, defect in ipairs(ledger.defects) do
        assert(type(defect.id) == "string" and defect.id ~= "", "defect has no stable ID")
        assert(defect.id == FIXED_DEFECTS[index], "historical defect ledger changed at entry " .. index)
        assert(not seenDefects[defect.id], "duplicate defect ID " .. defect.id)
        seenDefects[defect.id] = true
        assert(type(defect.description) == "string" and defect.description ~= "", "defect has no description")
        local mechanism = assert(defect.mechanism, "defect has no equivalence mechanism")
        assert(
            type(defect.expectedWitnesses) == "table"
            and #defect.expectedWitnesses == 1
            and defect.expectedWitnesses[1] == mechanism.testId,
            "defect must name its exact witness ID"
        )
        for _, witness in ipairs(defect.expectedWitnesses) do
            assert(not seenWitnesses[witness], "duplicate defect witness " .. witness)
            seenWitnesses[witness] = defect.id
        end
        assert(
            type(defect.acceptedFailureModes) == "table" and #defect.acceptedFailureModes > 0,
            "defect has no accepted failure mode"
        )
        local failureModes = {}
        for _, failureMode in ipairs(defect.acceptedFailureModes) do
            assert(type(failureMode) == "string" and failureMode ~= "", "defect has an invalid failure mode")
            assert(not failureModes[failureMode], "defect has a duplicate failure mode")
            failureModes[failureMode] = true
        end
        assert(
            type(mechanism.testId) == "string" and mechanism.testId:match("^[%w_.-]+/[%w_.-]+$"),
            "defect mechanism has no stable exact test ID"
        )
        assert(mechanism.productionFlag == nil, "defect mutation must not add a production flag")
        if mechanism.kind == "preserved-test" then
            assert(
                type(mechanism.evidence) == "string" and mechanism.evidence ~= "",
                "preserved test has no evidence path"
            )
            assert(
                type(mechanism.historicalCommit) == "string" and mechanism.historicalCommit:match("^[0-9a-f]+$"),
                "preserved test has no historical commit"
            )
            assert(mechanism.implemented == true, "preserved test mutation is not implemented")
            assert(
                type(mechanism.operation) == "string" and mechanism.operation ~= "",
                "preserved test has no mutation"
            )
            assert(
                type(mechanism.killMarker) == "string"
                and mechanism.killMarker:find("SIMD_EQUIVALENCE_KILL:" .. defect.id .. ":", 1, true) == 1,
                "preserved test has no defect-specific kill marker"
            )
        elseif mechanism.kind == "generated-fixture-mutation" then
            assert(type(mechanism.fixture) == "string" and mechanism.fixture ~= "", "generated mutation has no fixture")
            assert(
                type(mechanism.operation) == "string" and mechanism.operation ~= "",
                "generated mutation has no operation"
            )
            assert(
                type(mechanism.historicalCommit) == "string" and mechanism.historicalCommit:match("^[0-9a-f]+$"),
                "generated mutation has no historical commit"
            )
            assert(
                type(mechanism.validator) == "string" and mechanism.validator ~= "",
                "generated mutation has no validator"
            )
            assert(mechanism.implemented == true, "generated fixture mutation is not implemented")
            assert(
                type(mechanism.killMarker) == "string"
                and mechanism.killMarker:find("SIMD_EQUIVALENCE_KILL:" .. defect.id .. ":", 1, true) == 1,
                "generated mutation has no defect-specific kill marker"
            )
        else
            error("defect mechanism must be a preserved test or generated fixture mutation", 0)
        end
        local markerPrefix = "SIMD_EQUIVALENCE_KILL:" .. defect.id .. ":"
        local markerMode = mechanism.killMarker:sub(#markerPrefix + 1)
        assert(failureModes[markerMode], "defect kill marker does not name an accepted failure mode")
    end

    return seenWitnesses
end

function M.load(manifestPath, ledgerPath)
    manifestPath = manifestPath or directory .. "/coverage-obligations.json"
    local manifest = json(manifestPath)
    assert(manifest.schemaVersion == 1, "unsupported coverage obligation schema")
    assert(
        type(manifest.requirements) == "table" and #manifest.requirements > 0,
        "coverage manifest has no requirements"
    )
    local ledger = json(ledgerPath or directory .. "/defect-ledger.json")
    local ledgerWitnesses = validateLedger(ledger)
    local ids = {}
    for _, requirement in ipairs(manifest.requirements) do
        assert(type(requirement.id) == "string" and requirement.id ~= "", "coverage requirement has no ID")
        assert(not ids[requirement.id], "duplicate coverage requirement " .. requirement.id)
        ids[requirement.id] = requirement
        assert(requirement.gate == "migration" or requirement.gate == "equivalence", "invalid coverage gate")
        assert(
            requirement.scope == "local" or requirement.scope == "fleet" or requirement.scope == "release-only",
            "invalid coverage scope"
        )
        assert(
            type(requirement.description) == "string" and requirement.description ~= "",
            "coverage requirement has no description"
        )
        expandRequirement(manifest, requirement, ledger)
    end

    return manifest, ledger, ledgerWitnesses
end

local function positive(value)
    return type(value) == "number" and value > 0
end

local function hostClass(report, row)
    if type(report.hostClass) == "string" then
        return report.hostClass
    end
    local executionHost = row and row.execution and row.execution.host or {}
    local reportedHost = tostring(report.host or "") .. " " .. tostring(row and row.target or "")
    local osName = tostring(executionHost.os or reportedHost):lower()
    local arch = tostring(executionHost.arch or (row and row.target) or report.host or ""):lower()
    local osClass = (osName:find("darwin", 1, true) or osName:find("osx", 1, true)) and "macos"
        or (osName:find("windows", 1, true) or osName:find("mingw", 1, true) or osName:find("msys", 1, true))
        and "windows"
        or osName:find("linux", 1, true) and "linux"
    local archClass = (arch:find("arm64", 1, true) or arch:find("aarch64", 1, true)) and "arm64"
        or (arch:find("x64", 1, true) or arch:find("x86_64", 1, true) or arch:find("amd64", 1, true)) and "x64"
    if osClass and archClass then
        return osClass .. "-" .. archClass
    end

    return nil
end

local function nativePrefix(report, row, revision)
    return table.concat(
        {"legacy/native", revision, hostClass(report, row) or "unknown-host", row.dialect or "unknown-compiler",},
        "/"
    )
end

local function primitiveGroups(coverage)
    local groups = {}
    if type(coverage) ~= "table" then
        return groups
    end
    for _, item in ipairs(coverage) do
        if type(item) == "table" then
            local group = item.family or (item.operations and "lanes")
            if group then
                groups[group == "convert" and "conversions" or group] = true
            end
        end
    end

    return groups
end

local function newCollector()
    return {witnesses = {}, invalid = {}, witnessIds = {}, legacyIds = {}}
end

local function invalidate(collector, message)
    collector.invalid[#collector.invalid + 1] = message
end

local function add(collector, obligation, witness, dimensions, sourceName)
    if type(witness) ~= "string" or witness == "" then
        invalidate(collector, sourceName .. ": witness has no stable ID")
        return
    elseif collector.witnessIds[witness] then
        invalidate(collector, sourceName .. ": duplicate witness ID " .. witness)
        return
    end
    collector.witnessIds[witness] = true
    collector.witnesses[
        #collector.witnesses + 1
    ] = {obligation = obligation, id = witness, dimensions = dimensions, source = sourceName,}
end

local function legacyId(prefix, obligation, dimensions)
    local parts = {prefix, obligation}
    for _, name in ipairs(sortedKeys(dimensions)) do
        parts[#parts + 1] = name .. "=" .. tostring(dimensions[name])
    end

    return table.concat(parts, "/")
end

local function addLegacy(collector, prefix, obligation, dimensions, sourceName)
    local id = legacyId(prefix, obligation, dimensions)
    if not collector.legacyIds[id] then
        collector.legacyIds[id] = true
        add(collector, obligation, id, dimensions, sourceName)
    end
end

local REPRESENTATIONS = {"native-single", "composite-exact", "composite-remainder", "preferred"}

local function elementCategory(element)
    if element == "float" or element == "number" then
        return "floating"
    elseif element == "int64" then
        return "wide-signed-integer"
    elseif element == "uint64" then
        return "wide-unsigned-integer"
    elseif element:match("^uint") then
        return "unsigned-integer"
    end

    return "signed-integer"
end

local function elementBits(element)
    return element == "float" and 32 or element == "number" and 64 or tonumber(element:match("%d+"))
end

local function vectorBits(tier)
    return tier == "avx512f" and 512 or tier == "avx2" and 256 or 128
end

local function representationsFor(lanes, element, tier)
    local found = {}
    local chunk = vectorBits(tier) / elementBits(element)
    for _, lane in ipairs(lanes or {}) do
        if lane == "preferred" then
            found.preferred = true
        elseif lane <= chunk then
            found["native-single"] = true
        elseif lane % chunk == 0 then
            found["composite-exact"] = true
        else
            found["composite-remainder"] = true
        end
    end

    return found, chunk
end

local function addOperationCase(collector, prefix, backend, operationCase, representations, sourceName)
    for _, representation in ipairs(REPRESENTATIONS) do
        if representations[representation] then
            addLegacy(
                collector,
                prefix,
                "simd.operation-semantics",
                {backend = backend, operationCase = operationCase, representation = representation},
                sourceName
            )
        end
    end
end

local function addPrimitiveCoverage(collector, prefix, backend, element, lanes, coverage, tier, sourceName)
    local groups = primitiveGroups(coverage)
    local representations, chunk = representationsFor(lanes, element, tier)
    for _, lane in ipairs(lanes or {}) do
        addLegacy(
            collector,
            prefix,
            "simd.species-inventory",
            {backend = backend, element = element, lane = lane},
            sourceName
        )
    end
    local category = elementCategory(element)
    addOperationCase(collector, prefix, backend, "common/" .. category, representations, sourceName)
    if category == "floating" and (groups.bitpatterns or groups.maps) then
        addOperationCase(collector, prefix, backend, "floating-special/floating", representations, sourceName)
    elseif category ~= "floating" and groups.integeredges then
        addOperationCase(collector, prefix, backend, "integer/" .. category, representations, sourceName)
    end
    if groups.conversions then
        for _, item in ipairs(coverage or {}) do
            if type(item) == "table" and (item.family == "convert" or item.family == "conversions") then
                for _, destination in ipairs(item.destinations or {}) do
                    addLegacy(
                        collector,
                        prefix,
                        "simd.conversions",
                        {backend = backend, source = item.source or element, destination = destination},
                        sourceName
                    )
                end
            end
        end
    end
    if #lanes > 0 then
        for _, tailCase in ipairs({"zero", "one", "logical-minus-one", "logical", "every-tail-representative"}) do
            addLegacy(collector, prefix, "simd.tail-semantics", {backend = backend, tailCase = tailCase}, sourceName)
        end
        if representations["composite-exact"] or representations["composite-remainder"] then
            for _, tailCase in ipairs({"chunk-minus-one", "chunk", "chunk-plus-one"}) do
                addLegacy(
                    collector,
                    prefix,
                    "simd.tail-semantics",
                    {backend = backend, tailCase = tailCase},
                    sourceName
                )
            end
        end
        for boundary in pairs(representations) do
            addLegacy(collector, prefix, "simd.representation-boundary", {boundary = boundary}, sourceName)
        end
        local selected = {}
        for _, lane in ipairs(lanes) do
            selected[lane] = true
        end
        if category == "floating" and tier == "avx2" and selected[chunk] then
            addLegacy(
                collector,
                prefix,
                "simd.representation-boundary",
                {boundary = "complete-256-bit-float"},
                sourceName
            )
        end
        if selected[64] then
            addLegacy(collector, prefix, "simd.representation-boundary", {boundary = "mask-64-lanes"}, sourceName)
        end
        if tier == "avx512f" and groups.memory and selected[chunk] then
            addLegacy(
                collector,
                prefix,
                "simd.representation-boundary",
                {boundary = "avx512-gather-scatter"},
                sourceName
            )
        elseif tier == "neon" and groups.memory and selected[chunk] then
            addLegacy(collector, prefix, "simd.representation-boundary", {boundary = "neon-field-pairs"}, sourceName)
        end
        if selected[chunk - 1] and selected[chunk] and selected[chunk + 1] then
            addLegacy(
                collector,
                prefix,
                "simd.representation-boundary",
                {boundary = "target-vector-ceiling"},
                sourceName
            )
            addLegacy(collector, prefix, "simd.representation-boundary", {boundary = "frame-width"}, sourceName)
        end
    end
end

local function addReducerCoverage(collector, prefix, backend, element, lanes, tier, sourceName)
    local representations = representationsFor(lanes, element, tier)
    addOperationCase(collector, prefix, backend, "reducers/" .. elementCategory(element), representations, sourceName)
end

local function validateExecution(execution, label)
    return type(execution) == "table"
        and execution.ok == true
        and positive(execution.cases)
        and positive(execution.probes)
        and positive(execution.nativeCalls)
        or nil, label .. " has no completed execution proof"
end

local function validateAlgorithmExecution(execution, label)
    return type(execution) == "table"
        and execution.ok == true
        and positive(execution.cases)
        and positive(execution.nativeCalls)
        or nil, label .. " has no completed execution proof"
end

local function nativeReport(collector, report, sourceName)
    if report.schemaVersion ~= 2 or type(report.selection) ~= "table" or type(report.rows) ~= "table" then
        return false
    end
    local revision = tostring(report.revision or "unknown")
    for _, row in ipairs(report.rows) do
        if row.status == "failed" then
            invalidate(
                collector,
                sourceName .. ": failed native matrix row " .. tostring(row.family) .. "/" .. tostring(row.element)
            )
        elseif row.status == "executed" then
            local sourcePrefix = nativePrefix(report, row, revision)
            local executionOk, executionProblem
            if row.family == "algorithms" then
                executionOk, executionProblem = validateAlgorithmExecution(row.execution, "native algorithm row")
            else
                executionOk, executionProblem = validateExecution(row.execution, "native row")
            end
            local rowValid = executionOk
            if not executionOk then
                invalidate(collector, sourceName .. ": " .. executionProblem)
            elseif row.family == "algorithms" then
                local dimensions = {backend = "native", algorithm = row.element, tier = row.tier}
                addLegacy(collector, sourcePrefix .. "/route=native", "simd.native.algorithm", dimensions, sourceName)
            else
                local scalarOk, scalarProblem = validateExecution(row.execution.scalarC, "scalar-C row")
                if not scalarOk then
                    invalidate(collector, sourceName .. ": " .. scalarProblem)
                    rowValid = nil
                else
                    local prefix = sourcePrefix
                        .. "/routes=simd+scalar-c/"
                        .. row.tier
                        .. "/"
                        .. row.family
                        .. "/"
                        .. row.element
                    if row.family == "primitives" then
                        addPrimitiveCoverage(
                            collector,
                            prefix,
                            "native",
                            row.element,
                            report.selection.lanes,
                            row.execution.coverage,
                            row.tier,
                            sourceName
                        )
                    elseif row.family == "reducers" then
                        addReducerCoverage(
                            collector,
                            prefix,
                            "native",
                            row.element,
                            report.selection.lanes,
                            row.tier,
                            sourceName
                        )
                    end
                end
            end
            if rowValid then
                local host = hostClass(report, row)
                if host then
                    addLegacy(collector, sourcePrefix, "simd.native.host", {host = host}, sourceName)
                end
                addLegacy(collector, sourcePrefix, "simd.native.tier", {tier = row.tier}, sourceName)
                if row.dialect == "clang" or row.dialect == "gcc" then
                    addLegacy(
                        collector,
                        sourcePrefix,
                        "simd.native.compiler-dialect",
                        {compiler = row.dialect},
                        sourceName
                    )
                end
            end
        end
    end
    for _, boundary in ipairs(report.runtimeBoundaries or {}) do
        local dimensions = {target = boundary.target, status = boundary.status}
        addLegacy(collector, "legacy/native/" .. revision, "simd.runtime-boundary", dimensions, sourceName)
    end

    return true
end

local function wasmSummary(collector, report, sourceName)
    if report.requested_wasm_matrix_complete ~= true or type(report.selection) ~= "table" then
        return false
    end
    local revision = tostring(report.revision or "unknown")
    for _, row in ipairs(report.rows or {}) do
        local executionOk, executionProblem = validateExecution(row.execution, "Wasm SIMD row")
        local scalarOk, scalarProblem = validateExecution(row.scalarC, "Wasm scalar-C row")
        if not executionOk or not scalarOk then
            invalidate(collector, sourceName .. ": " .. tostring(executionProblem or scalarProblem))
        else
            local prefix = "legacy/wasm/" .. revision .. "/routes=simd+scalar-c/" .. row.family .. "/" .. row.element
            if row.family == "primitives" then
                addPrimitiveCoverage(
                    collector,
                    prefix,
                    "wasm",
                    row.element,
                    report.selection.lanes,
                    row.execution.coverage,
                    "simd128",
                    sourceName
                )
            elseif row.family == "reducers" then
                addReducerCoverage(
                    collector,
                    prefix,
                    "wasm",
                    row.element,
                    report.selection.lanes,
                    "simd128",
                    sourceName
                )
            end
        end
    end
    local counted = report.counted or {}
    for route, execution in pairs({simd = counted.execution, ["scalar-c"] = counted.scalarC}) do
        local ok = validateExecution(execution, "Wasm counted " .. route)
        if ok then
            local dimensions = {backend = "wasm", route = route}
            addLegacy(
                collector,
                "legacy/wasm/" .. revision .. "/route=" .. route,
                "simd.wasm.counted-runtime",
                dimensions,
                sourceName
            )
        else
            invalidate(collector, sourceName .. ": Wasm counted " .. route .. " has no completed execution proof")
        end
    end

    return true
end

local function wasmAggregate(collector, report, sourceName)
    if report.full_wasm_inventory_complete == nil then
        return false
    end
    if report.full_wasm_inventory_complete ~= true then
        invalidate(collector, sourceName .. ": incomplete Wasm matrix aggregate")
    end
    for index, row in ipairs(report.rows or {}) do
        local summary = row.summary or row
        if not wasmSummary(collector, summary, sourceName .. "#" .. index) then
            invalidate(collector, sourceName .. ": invalid Wasm shard summary")
        end
    end

    return true
end

local function wasmAlgorithms(collector, report, sourceName)
    if report.full_wasm_algorithm_inventory_complete == nil then
        return false
    end
    if report.full_wasm_algorithm_inventory_complete ~= true then
        invalidate(collector, sourceName .. ": incomplete Wasm algorithm inventory")
    end
    local revision = tostring(report.revision or "unknown")
    for _, row in ipairs(report.rows or {}) do
        local ok, problem = validateExecution(row.execution, "Wasm algorithm " .. tostring(row.algorithm))
        if ok then
            local dimensions = {backend = "wasm", algorithm = row.algorithm}
            addLegacy(
                collector,
                "legacy/wasm-algorithm/" .. revision .. "/route=wasm",
                "simd.wasm.algorithm",
                dimensions,
                sourceName
            )
        else
            invalidate(collector, sourceName .. ": " .. problem)
        end
    end

    return true
end

local function harnessReport(collector, report, sourceName)
    if type(report.tests) ~= "table" then
        return false
    end
    if positive(report.failed) then
        invalidate(collector, sourceName .. ": test report contains failures")
    end
    for _, case in ipairs(report.tests) do
        if case.status == "passed" then
            for _, fact in ipairs(case.facts or {}) do
                if fact.name == "coverage.witness" then
                    local value = fact.value
                    if type(value) ~= "table"
                        or type(value.obligation) ~= "string"
                        or type(value.dimensions) ~= "table"
                    then
                        invalidate(
                            collector,
                            sourceName .. ": malformed coverage.witness fact in " .. tostring(case.id)
                        )
                    else
                        add(
                            collector,
                            value.obligation,
                            value.id,
                            value.dimensions,
                            sourceName .. ":" .. tostring(case.id)
                        )
                    end
                end
            end
        end
    end

    return true
end

local function collectReport(collector, report, sourceName)
    if harnessReport(collector, report, sourceName)
        or nativeReport(collector, report, sourceName)
        or wasmAggregate(collector, report, sourceName)
        or wasmSummary(collector, report, sourceName)
        or wasmAlgorithms(collector, report, sourceName)
    then
        return
    end
    invalidate(collector, sourceName .. ": unrecognized coverage report")
end

local function gateIncludes(selected, requirement)
    return requirement.gate == "migration" or selected == "equivalence"
end

function M.validate(reports, options)
    options = options or {}
    local gate = options.gate or "migration"
    assert(gate == "migration" or gate == "equivalence", "gate must be migration or equivalence")
    local manifest, ledger, ledgerWitnesses = M.load(options.manifest, options.ledger)
    local collector = newCollector()
    for index, item in ipairs(reports) do
        local report = item.report or item
        collectReport(collector, report, item.name or ("report-" .. index))
    end

    local requirements, byId = {}, {}
    for _, requirement in ipairs(manifest.requirements) do
        byId[requirement.id] = requirement
        if gateIncludes(gate, requirement) then
            local combinations, names = expandRequirement(manifest, requirement, ledger)
            for _, dimensions in ipairs(combinations) do
                local key = dimensionKey(requirement.id, dimensions, names)
                requirements[
                    key
                ] = {obligation = requirement.id, dimensions = dimensions, names = names, witnesses = {},}
            end
        end
    end

    for _, witness in ipairs(collector.witnesses) do
        local requirement = byId[witness.obligation]
        if not requirement then
            invalidate(collector, witness.source .. ": unknown coverage obligation " .. tostring(witness.obligation))
        elseif gateIncludes(gate, requirement) then
            local _, names = expandRequirement(manifest, requirement, ledger)
            local ok, key = pcall(dimensionKey, requirement.id, witness.dimensions, names)
            local required = ok and requirements[key] or nil
            if not required then
                invalidate(collector, witness.source .. ": witness dimensions do not match " .. requirement.id)
            elseif requirement.ledger and ledgerWitnesses[witness.id] ~= witness.dimensions.defect then
                invalidate(collector, witness.source .. ": defect witness ID does not match the ledger")
            else
                required.witnesses[#required.witnesses + 1] = witness.id
            end
        end
    end

    local missing, covered = {}, 0
    for _, key in ipairs(sortedKeys(requirements)) do
        local requirement = requirements[key]
        if #requirement.witnesses == 0 then
            missing[#missing + 1] = {obligation = requirement.obligation, dimensions = requirement.dimensions}
        else
            covered = covered + 1
        end
    end
    table.sort(collector.invalid)

    return {
        schemaVersion = 1,
        ok = #missing == 0 and #collector.invalid == 0,
        gate = gate,
        required = covered + #missing,
        covered = covered,
        missing = missing,
        invalid = collector.invalid,
        witnesses = #collector.witnesses,
    }
end

function M.validateFiles(paths, options)
    local reports = {}
    for _, path in ipairs(paths) do
        reports[#reports + 1] = {name = path, report = json(path)}
    end

    return M.validate(reports, options)
end

local function main(arguments)
    local options, paths = {}, {}
    local asJson = false
    for _, argument in ipairs(arguments) do
        if argument == "--json" then
            asJson = true
        elseif argument:match("^%-%-gate=") then
            options.gate = argument:sub(#"--gate=" + 1)
        elseif argument:match("^%-%-manifest=") then
            options.manifest = argument:sub(#"--manifest=" + 1)
        elseif argument:match("^%-%-ledger=") then
            options.ledger = argument:sub(#"--ledger=" + 1)
        elseif argument:sub(1, 1) == "-" then
            io.stderr:write("unknown option: " .. argument .. "\n")
            return 2
        else
            paths[#paths + 1] = argument
        end
    end
    if #paths == 0 then
        io.stderr:write("usage: luajit tests/simd/obligations.lua [--gate=migration|equivalence] REPORT...\n")
        return 2
    end
    local ok, result = pcall(M.validateFiles, paths, options)
    if not ok then
        io.stderr:write(tostring(result) .. "\n")
        return 2
    end
    if asJson then
        io.write(encode(result) .. "\n")
    elseif result.ok then
        io.write(
            (
                "SIMD obligations: %d/%d covered (%d witnesses)\n"
            ):format(result.covered, result.required, result.witnesses)
        )
    else
        io.stderr:write(
            (
                "SIMD obligations: %d/%d covered, %d invalid witnesses\n"
            ):format(result.covered, result.required, #result.invalid)
        )
    end

    return result.ok and 0 or 1
end

if ... ~= "tests.simd.obligations" then
    os.exit(main(arg))
end

return M
