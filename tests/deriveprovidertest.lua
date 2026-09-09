-- End-to-end coverage for public and compiler-shipped comptime providers.

local json = require("testjson")
local process = require("nupp.compiler.build.process")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local NUPP = HERE .. "/../bin/nupp"

local M = {}

-- One check for every fixture, rather than one check per fixture.
--
-- A `nupp check` of a single file in this repository costs about ten seconds of
-- processor time before it has looked at the file: the manifest is read, a
-- module index over a thousand sources is built, and the standard library the
-- fixture reaches is checked. The eight fixtures below asked for that eight
-- times between them, which was the whole cost of this suite.
--
-- `check` takes a list, so they are checked together and each case reads the
-- diagnostics naming its own file. That is more precise than the exit status it
-- replaced rather than less: a status says the batch failed, a file says which
-- fixture failed and how.
--
-- Two batches, because the answer they want is opposite. One is held to the
-- strict floor and must be clean; the other must be refused, which is what each
-- of its assertions is about, so a shared status would mean nothing there.
local function checkedTogether(flags, paths)
    local answered = nil

    return function(path)
        if not answered then
            local argv = {NUPP, "check", "--json"}
            for _, flag in ipairs(flags) do
                argv[#argv + 1] = flag
            end
            for _, each in ipairs(paths) do
                argv[#argv + 1] = each
            end
            local status, output = process.capture(argv)
            local ok, decoded = pcall(json.decode, output)
            assert(
                ok and type(decoded) == "table",
                (
                    "`nupp check %s` over %d fixtures wrote no JSON (status %s):\n%s"
                ):format(table.concat(flags, " "), #paths, tostring(status), output)
            )
            answered = decoded
        end
        local wanted = assert(path:match("([^/\\]+)$"))
        local mine = {}
        for _, diagnostic in ipairs(answered.diagnostics or {}) do
            local named = tostring(diagnostic.file or "")
            if named:sub(-#wanted) == wanted then
                mine[#mine + 1] = diagnostic
            end
        end

        return mine
    end
end

local STRICT = {
    ecs = HERE .. "/fixtures/ecsderiveconsumer.nupp",
    inspect = HERE .. "/fixtures/deriveinspect_consumer.nupp",
    exported = HERE .. "/fixtures/deriveexported_main.nupp",
    witness = HERE .. "/fixtures/witnessexported_main.nupp",
    custom = HERE .. "/../editors/playground/src/examples/custom-derive.nupp",
}

local REFUSED = {
    unsupported = HERE .. "/fixtures/deriveinspect_invalid.nupp",
    provider = HERE .. "/fixtures/deriveinvalidprovider.nupp",
    immutable = HERE .. "/fixtures/deriveimmutable.nupp",
}

local STRICT_BATCH = {STRICT.ecs, STRICT.inspect, STRICT.exported, STRICT.witness, STRICT.custom}
local REFUSED_BATCH = {REFUSED.unsupported, REFUSED.provider, REFUSED.immutable}

local strictly = checkedTogether({"--strict"}, STRICT_BATCH)
local refusals = checkedTogether({}, REFUSED_BATCH)

--- The strict batch reported nothing about this fixture.
local function checksStrictly(path, label)
    local diagnostics = strictly(path)
    if #diagnostics > 0 then
        local first = diagnostics[1]
        error(
            (
                "%s: %s reports %s: %s\n(checked strictly beside %d other fixtures)"
            ):format(label, path, tostring(first.code), tostring(first.message), #STRICT_BATCH - 1),
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
    local status, output = process.capture({NUPP, "run", path})
    assert(status == 0, ("%s: %s did not run:\n%s"):format(label, path, output))

    return output
end

function M.declaredProvidersPreserveNamesColumnsAndWitnessCapabilities()
    checksStrictly(STRICT.ecs, "the declared-provider consumer checks strictly")
    local output = ran(STRICT.ecs, "the declared-provider consumer runs")
    assert(output == "derived declarations\n", output)
end

function M.runsThePublicComptimeForwardingRecipeEndToEnd()
    checksStrictly(STRICT.inspect, "the forwarding consumer checks strictly")
    ran(STRICT.inspect, "the forwarding consumer runs")
    ran(HERE .. "/fixtures/derivelocal.nupp", "a local provider runs")

    refuses(REFUSED.unsupported, "NUPP2810", {at = "unsupported"}, "an unsupported provider input is refused")
    refuses(REFUSED.provider, "NUPP2809", {}, "an invalid provider declaration is refused")
    refuses(
        REFUSED.immutable,
        nil,
        {says = "cannot be assigned through"},
        "a provider that mutates its Info projection is refused"
    )
end

function M.attachesADeriveThroughAnExportWrapper()
    -- `@derive(...) export record R` decorates R, the way it does without the
    -- visibility; the export is a wrapper the annotation looks through.
    checksStrictly(STRICT.exported, "the exported-derive main checks strictly")
    local output = ran(STRICT.exported, "the exported-derive main runs")
    assert(output == "Point { x = 3 }\n", output)
end

function M.publishesAnExportedRecordAsItsWitness()
    -- Reached through its module, an exported record is the `Type<R>` its own
    -- scope binds, so a `Type<T>` directed API and a construction pack take it
    -- from either side of the boundary.
    checksStrictly(STRICT.witness, "the exported-witness main checks strictly")
    local output = ran(STRICT.witness, "the exported-witness main runs")
    assert(output == "true\t1\t2\nspawned\tnumber\n", output)
end

function M.runsAProviderThatDeclaresItsOwnMember()
    checksStrictly(STRICT.custom, "the playground custom-derive example checks strictly")
    local output = ran(STRICT.custom, "the playground custom-derive example runs")
    assert(output == "<User>\n", output)
end

return M
