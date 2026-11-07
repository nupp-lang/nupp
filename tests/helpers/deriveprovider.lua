-- End-to-end coverage for public and compiler-shipped comptime providers.

local json = require("testjson")
local process = require("nupp.compiler.process")

local HERE = require("helpers.paths").tests
local NUPP = require("nupp.compiler.fs").canonical(HERE .. "/../bin/nupp")

-- Semantic fixtures share a real project environment. The internal namespace
-- and outside-project cases retain their CLI boundaries in their own packages.
local projects = {}

local function projectAt(root)
    root = root or HERE .. "/.."
    projects[root] = projects[root] or require("helpers.contractproject").open(root)
    return projects[root]
end

local function checkedTogether(flags, paths, cwd)
    local answers = {}
    return function(path)
        if not answers[path] then
            local _, diagnostics = projectAt(cwd).check({path})
            answers[path] = diagnostics
        end

        return answers[path]
    end
end

local INTERNAL_ROOT = require("nupp.compiler.fs").canonical(HERE .. "/fixtures/derive-internal")
local STRICT = {
    ecs = INTERNAL_ROOT .. "/src/nupp/internal/ecsderiveconsumer.nupp",
    inspect = HERE .. "/fixtures/deriveinspect_consumer.nupp",
    exported = HERE .. "/fixtures/deriveexported_main.nupp",
    witness = HERE .. "/fixtures/witnessexported_main.nupp",
    annotationWitness = HERE .. "/fixtures/derivewitness_consumer.nupp",
    custom = HERE .. "/../editors/playground/src/examples/custom-derive.nupp",
}

local REFUSED = {
    unsupported = HERE .. "/fixtures/deriveinspect_invalid.nupp",
    provider = HERE .. "/fixtures/deriveinvalidprovider.nupp",
    immutable = HERE .. "/fixtures/deriveimmutable.nupp",
}

local STRICT_BATCH = {STRICT.inspect, STRICT.exported, STRICT.witness, STRICT.annotationWitness, STRICT.custom,}
local REFUSED_BATCH = {REFUSED.unsupported, REFUSED.provider, REFUSED.immutable}

local strictly = checkedTogether({}, STRICT_BATCH)
local internally = checkedTogether({}, {STRICT.ecs}, INTERNAL_ROOT)
local refusals = checkedTogether({}, REFUSED_BATCH)

--- The strict batch reported nothing about this fixture.
local function checksStrictly(path, label)
    local diagnostics = (path == STRICT.ecs and internally or strictly)(path)
    local count = path == STRICT.ecs and 1 or #STRICT_BATCH
    if #diagnostics > 0 then
        local first = diagnostics[1]
        error(
            (
                "%s: %s reports %s: %s\n(checked strictly beside %d other fixtures)"
            ):format(label, path, tostring(first.code), tostring(first.message), count - 1),
            2
        )
    end
end

--- The bytes a diagnostic's range covers, read from the file it names.
---
--- Rendered output quotes the offending line, so a test asserting on that text
--- could pass on the source rather than on what was said about it: matching
--- "unsupported" below found the field's own name in the echoed snippet and
--- would have kept matching whatever the compiler concluded about it. What a
--- structured diagnostic offers instead is the range, which says the finding is
--- about that field and nothing else.
local function covered(path, diagnostic)
    local file = io.open(path, "rb")
    if not file or not diagnostic.range then
        return ""
    end
    local source = file:read("*a")
    file:close()
    local from, to = diagnostic.range.start, diagnostic.range["end"]
    if not (from and to and from.offset and to.offset) then
        return ""
    end

    -- Offsets are 1-based and the end is one past the last byte, as everywhere
    -- a Nupp range is reported.

    return source:sub(from.offset, to.offset - 1)
end

--- The refusal batch reported this code against this fixture, at this name.
---
--- `wanted.at` is the source the diagnostic's range must cover and `wanted.says`
--- wording its message must carry; a refusal names one or the other.
local function refuses(path, code, wanted, label)
    local diagnostics = refusals(path)
    local beside = ("(refused beside %d other fixtures)"):format(#REFUSED_BATCH - 1)
    assert(#diagnostics > 0, ("%s: %s was accepted %s"):format(label, path, beside))
    local codes, sawError = {}, false
    local sawCode, sawWording, sawRange = code == nil, wanted.says == nil, wanted.at == nil
    for _, diagnostic in ipairs(diagnostics) do
        codes[#codes + 1] = tostring(diagnostic.code)
        sawError = sawError or diagnostic.severity == "error"
        if diagnostic.code == code then
            sawCode = true
        end
        if wanted.says and tostring(diagnostic.message):find(wanted.says, 1, true) then
            sawWording = true
        end
        if wanted.at and covered(path, diagnostic) == wanted.at then
            sawRange = true
        end
    end
    local reported = table.concat(codes, ", ")
    assert(sawError, ("%s: %s reported %s, none of them an error %s"):format(label, path, reported, beside))
    assert(sawCode, ("%s: %s reported %s rather than %s %s"):format(label, path, reported, tostring(code), beside))
    assert(
        sawWording,
        ("%s: %s reported %s but never said %q %s"):format(label, path, reported, tostring(wanted.says), beside)
    )
    assert(
        sawRange,
        ("%s: %s reported %s but never about %q %s"):format(label, path, reported, tostring(wanted.at), beside)
    )
end

--- Runs a fixture and answers what it printed.
local function ran(path, label)
    if path ~= STRICT.ecs then
        return projectAt().run(path, true)
    end
    local status, output = process.capture({NUPP, "run", path}, {cwd = INTERNAL_ROOT})
    assert(status == 0, ("%s: %s did not run:\n%s"):format(label, path, output))

    return output
end

return {
    json = json,
    process = process,
    HERE = HERE,
    NUPP = NUPP,
    checkedTogether = checkedTogether,
    INTERNAL_ROOT = INTERNAL_ROOT,
    STRICT = STRICT,
    REFUSED = REFUSED,
    STRICT_BATCH = STRICT_BATCH,
    REFUSED_BATCH = REFUSED_BATCH,
    strictly = strictly,
    internally = internally,
    refusals = refusals,
    checksStrictly = checksStrictly,
    covered = covered,
    refuses = refuses,
    ran = ran,
}
