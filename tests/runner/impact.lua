-- Runner-facing API for Tier 1 diff-directed test selection.
local diff = require("nupp.compiler.testimpact.diff")
local selection = require("nupp.compiler.testimpact.selection")
local store = require("nupp.compiler.testimpact.store")
local observe = require("nupp.compiler.testimpact.observe")

local impact = {
    discoverChanges = diff.discover,
    normalizePath = diff.normalizePath,
    select = selection.select,
    caseIdentity = store.caseIdentity,
}

local STAMP_FIELDS = {
    "project",
    "revision",
    "operatingSystem",
    "architecture",
    "runtime",
    "targetProfile",
    "suiteCatalog",
    "stableIds",
}

local function required(value, label)
    if type(value) ~= "string" or value == "" then
        return nil, label .. " must be a non-empty string"
    end
    return value
end

-- Builds the exact identity the binary store checks at read time. Nothing here
-- is inferred from the current process: the runner records what actually
-- produced the catalog and graph.
function impact.graphStamps(metadata)
    if type(metadata) ~= "table" then
        return nil, "test-impact graph metadata is missing"
    end
    local out = {}
    for _, field in ipairs(STAMP_FIELDS) do
        local value, problem = required(metadata[field], "test-impact " .. field)
        if not value then
            return nil, problem
        end
        out[field] = value
    end

    return out
end

function impact.cachePath(buildRoot)
    buildRoot = buildRoot or "build"
    assert(type(buildRoot) == "string" and buildRoot ~= "", "test-impact build root must be a string")
    return buildRoot:gsub("[\\/]+$", "") .. "/.nupp-test-impact.buf"
end

function impact.newObserver(metadata)
    return observe.new(metadata)
end

local function uncertaintyIdentity(value)
    if type(value) == "string" and value ~= "" then
        return value
    end
    if type(value) ~= "table" or type(value.code) ~= "string" or value.code == "" then
        return "invalid-uncertainty"
    end
    if type(value.detail) == "string" and value.detail ~= "" then
        return value.code .. ":" .. tostring(#value.detail) .. ":" .. value.detail
    end

    return value.code
end

local function addUncertainty(owner, value)
    owner._uncertainty[uncertaintyIdentity(value)] = true
end

local function rootsInto(owner, roots, modules)
    local valid = true
    for _, root in ipairs(roots or {}) do
        if type(root) ~= "table" or type(root.module) ~= "string" or root.module == "" then
            valid = false
        else
            local module = modules[root.module]
            if not module then
                module = {name = root.module, _paths = {}, _dependencies = {}}
                modules[root.module] = module
            end
            if type(root.path) == "string" and root.path ~= "" then
                module._paths[diff.normalizePath(root.path)] = true
            end
            local found = false
            for _, provenance in ipairs(root.provenance or {}) do
                if type(provenance) == "string" and provenance ~= "" then
                    owner._roots[root.module .. "\0" .. provenance] = {module = root.module, provenance = provenance,}
                    found = true
                end
            end
            if not found then
                valid = false
            end
        end
    end

    return valid
end

local function sortedKeys(values)
    local out = {}
    for value in pairs(values) do
        out[#out + 1] = value
    end
    table.sort(out)

    return out
end

local function valuesBySortedKey(values)
    local out = {}
    for _, key in ipairs(sortedKeys(values)) do
        out[#out + 1] = values[key]
    end

    return out
end

local function finishOwner(owner)
    owner.roots = valuesBySortedKey(owner._roots)
    owner.uncertainty = sortedKeys(owner._uncertainty)
    owner._roots = nil
    owner._uncertainty = nil
end

local function newOwner(sliceSafe)
    return {sliceSafe = sliceSafe == true, _roots = {}, _uncertainty = {}, _seen = false}
end

-- Merges private worker or child fragments into the authoritative store input.
-- Suite metadata is the complete discovery catalog. Its `identity` is the name
-- observation scopes use, while `path` is the stable repository path persisted
-- in the graph.
function impact.mergeFragmentsToObservation(fragments, suiteMetadata, stamps, flags)
    flags = flags or {}
    local observation = {
        stamps = stamps,
        paths = {},
        modules = {},
        suites = {},
        complete = flags.complete == true,
        successful = flags.successful == true,
        unfiltered = flags.unfiltered == true,
    }
    local problemCounts = {}
    local problemExamples = {}

    local function incomplete(code, example)
        observation.complete = false
        problemCounts[code] = (problemCounts[code] or 0) + 1
        problemExamples[code] = problemExamples[code] or example
    end

    local function finishProblems()
        local problems = {}
        for _, code in ipairs(sortedKeys(problemCounts)) do
            problems[#problems + 1] = {code = code, count = problemCounts[code], example = problemExamples[code],}
        end
        observation.problems = problems
    end

    if flags.complete ~= true then
        incomplete("incomplete-run", "the producing run did not cover every discovered suite")
    end
    if type(fragments) ~= "table" or type(suiteMetadata) ~= "table" then
        incomplete("invalid-input", "fragments and suite metadata must be tables")
        finishProblems()
        return observation
    end

    local modules = {}
    local suites = {}
    for _, metadata in ipairs(suiteMetadata) do
        if type(metadata) ~= "table" then
            incomplete("invalid-suite-metadata", tostring(metadata))
        else
            local identity = metadata.identity or metadata.path
            local path = metadata.path
            if type(identity) ~= "string"
                or identity == ""
                or type(path) ~= "string"
                or path == ""
                or suites[identity] ~= nil
            then
                incomplete("invalid-suite-metadata", tostring(identity or path))
            else
                local suite = newOwner(metadata.sliceSafe)
                suite.path = diff.normalizePath(path)
                suite.cases = {}
                suite._cases = {}
                suites[identity] = suite
                for _, caseMetadata in ipairs(metadata.cases or {}) do
                    local id = type(caseMetadata) == "table" and caseMetadata.id or nil
                    if type(id) ~= "string" or id == "" or suite._cases[id] ~= nil then
                        incomplete("invalid-case-metadata", tostring(identity) .. "/" .. tostring(id))
                    else
                        local case = newOwner(caseMetadata.sliceSafe)
                        case.id = id
                        suite._cases[id] = case
                    end
                end
            end
        end
    end

    local expectedRun = flags.runId
    local expectedPlatform = flags.platform
    if type(expectedRun) ~= "string"
        or expectedRun == ""
        or type(expectedPlatform) ~= "string"
        or expectedPlatform == ""
    then
        incomplete("invalid-run-identity", tostring(expectedRun) .. "/" .. tostring(expectedPlatform))
    end

    for _, fragment in ipairs(fragments) do
        if type(fragment) ~= "table"
            or fragment.format ~= observe.FORMAT
            or fragment.runId ~= expectedRun
            or fragment.platform ~= expectedPlatform
        then
            incomplete("foreign-fragment", tostring(type(fragment) == "table" and fragment.runId or fragment))
        else
            for _, dependencyRecord in ipairs(fragment.dependencies or {}) do
                if type(dependencyRecord) ~= "table"
                    or type(dependencyRecord.module) ~= "string"
                    or dependencyRecord.module == ""
                then
                    incomplete("invalid-dependency-record", tostring(dependencyRecord))
                else
                    local module = modules[dependencyRecord.module]
                    if not module then
                        module = {name = dependencyRecord.module, _paths = {}, _dependencies = {}}
                        modules[dependencyRecord.module] = module
                    end
                    for _, dependency in ipairs(dependencyRecord.dependencies or {}) do
                        if type(dependency) == "table"
                            and type(dependency.module) == "string"
                            and dependency.module ~= ""
                        then
                            module._dependencies[dependency.module] = true
                            if not modules[dependency.module] then
                                modules[
                                    dependency.module
                                ] = {name = dependency.module, _paths = {}, _dependencies = {},}
                            end
                            if type(dependency.path) == "string" and dependency.path ~= "" then
                                modules[dependency.module]._paths[diff.normalizePath(dependency.path)] = true
                            end
                        else
                            incomplete("invalid-dependency-edge", tostring(dependency))
                        end
                    end
                end
            end
            for _, ownerFragment in ipairs(fragment.owners or {}) do
                local suite = type(ownerFragment) == "table" and suites[ownerFragment.suite] or nil
                if not suite then
                    incomplete(
                        "unknown-suite-owner",
                        tostring(type(ownerFragment) == "table" and ownerFragment.suite or ownerFragment)
                    )
                else
                    local owner = suite
                    if ownerFragment.caseId ~= nil then
                        owner = type(ownerFragment.caseId) == "string" and suite._cases[ownerFragment.caseId] or nil
                        if not owner then
                            incomplete(
                                "unknown-case-owner",
                                tostring(ownerFragment.suite) .. "/" .. tostring(ownerFragment.caseId)
                            )
                        end
                    end
                    if owner then
                        owner._seen = true
                        if not rootsInto(owner, ownerFragment.roots, modules) then
                            incomplete(
                                "invalid-owner-root",
                                tostring(ownerFragment.suite) .. "/" .. tostring(ownerFragment.caseId)
                            )
                        end
                        for _, uncertain in ipairs(ownerFragment.uncertainty or {}) do
                            if type(uncertain) == "table"
                                and type(uncertain.code) == "string"
                                and uncertain.code ~= ""
                            then
                                addUncertainty(owner, uncertain)
                            else
                                incomplete(
                                    "invalid-uncertainty",
                                    tostring(ownerFragment.suite) .. "/" .. tostring(ownerFragment.caseId)
                                )
                            end
                        end
                    end
                end
            end
        end
    end

    for _, moduleName in ipairs(sortedKeys(modules)) do
        local module = modules[moduleName]
        local paths = sortedKeys(module._paths)
        if #paths > 1 then
            incomplete("ambiguous-module-path", moduleName .. ": " .. table.concat(paths, ", "))
        end
        observation.modules[
            #observation.modules + 1
        ] = {name = module.name, path = paths[1], dependencies = sortedKeys(module._dependencies),}
    end
    for _, identity in ipairs(sortedKeys(suites)) do
        local suite = suites[identity]
        for _, caseId in ipairs(sortedKeys(suite._cases)) do
            local case = suite._cases[caseId]
            if not case._seen then
                incomplete("unseen-case", identity .. "/" .. caseId)
            end
            case._seen = nil
            finishOwner(case)
            suite.cases[#suite.cases + 1] = case
        end
        suite._cases = nil
        if not suite._seen then
            incomplete("unseen-suite", identity)
        end
        suite._seen = nil
        finishOwner(suite)
        observation.suites[#observation.suites + 1] = suite
    end

    finishProblems()

    return observation
end

function impact.load(buildRoot, stamps)
    return store.load(impact.cachePath(buildRoot), stamps)
end

function impact.publish(buildRoot, observation)
    return store.publish(impact.cachePath(buildRoot), observation)
end

return impact
