local paths = require("helpers.paths")
local json = require("serde.json")
local test = require("assert")
local validator = dofile(paths.absoluteTests .. "/core/guests/selfbuildoutput.lua")
local accepts = validator.compilerselfbuild
local M = {}

local function report()
    return {
        ok = true,
        target = "dist",
        diagnostics = {},
        timing = {
            totalMs = 1010,
            compiledModules = 2,
            reusedModules = 3,
            phases = {{name = "check", durationMs = 800}, {name = "bundle", durationMs = 210}},
            slowest = {{module = "nupp.tools.main", durationMs = 800}},
        },
    }
end

local function output(value, progress)
    return "0.000 compiler target dist: start core build\n" .. (
        progress
        or "  resolving dependencies\n  [ 50%] [1/2] checking src/nupp/tools/main.nupp\n"
        .. "built dist in 1.0s: 2 compiled, 3 reused\n  check 800ms  bundle 210ms\n"
        .. "  slowest\n    nupp.tools.main  800ms\n"
    ) .. json.encodevalue(value or report()) .. "\n" .. "1.123 compiler target dist: finished with status 0\n"
end

function M.acceptsTheCompleteReportWithExpectedProgressAndMarks()
    assert(accepts(output()))
    assert(accepts(output():gsub("\n", "\r\n")))
    local reused = report()
    reused.timing.compiledModules = 0
    reused.timing.slowest = {}
    assert(accepts(output(reused, "built dist in 1.0s: 3 modules reused\n")))
end

function M.acceptsTheActualBuildReporterWithoutRunningABuild()
    local fixture = require("helpers.buildprogressfixture")
    local path = os.tmpname()
    local reporter, stream = fixture.reporterTo(path, "always")
    reporter:expect(1)
    reporter:step("checking src/nupp/tools/main.nupp")
    reporter:counted(1, 0)
    reporter:finish("built", "dist")
    stream:close()
    local value = report()
    value.timing = reporter:timing()
    local printed = fixture.readAll(path)
    os.remove(path)
    assert(accepts(output(value, printed)), printed)
end

function M.rejectsFailedWrongTargetOrDiagnosticReports()
    for _, change in ipairs({
        function(value)
            value.ok = false
        end,
        function(value)
            value.target = "docs"
        end,
        function(value)
            value.diagnostics = {
                {severity = "error", message = "reject this diagnostic", fixes = {}, notes = {}, related = {}}
            }
        end,
        function(value)
            value.diagnostics = nil
        end,
        function(value)
            value.timing.parallel = {mode = "parallel", workers = "invalid"}
        end,
        function(value)
            value.timing.phases = "invalid"
        end,
    }) do
        local value = report()
        change(value)
        test.eq(accepts(output(value)), false)
    end
end

function M.acceptsValidWarningsAndNotesWithoutChangingTheReport()
    local value = report()
    value.diagnostics = {
        {
            severity = "warning",
            code = "NUPP2000",
            message = "visible warning",
            fixes = {},
            notes = {"explanation"},
            related = {}
        },
        {severity = "note", message = "visible note", fixes = {}, notes = {}, related = {}},
    }
    local encoded = json.encodevalue(value)
    local printed = output(value)
    assert(accepts(printed))
    assert(printed:find(encoded, 1, true), "the complete diagnostic report remains visible")
end

function M.rejectsMalformedDiagnosticRecords()
    for _, diagnostic in ipairs({
        {severity = "warning", fixes = {}, notes = {}, related = {}},
        {severity = "unknown", message = "bad severity", fixes = {}, notes = {}, related = {}},
        {severity = "warning", message = "missing required arrays"},
        {severity = "warning", message = "bad notes", fixes = {}, notes = {42}, related = {}},
        {severity = "warning", message = "bad fix", fixes = {{title = "missing edits"}}, notes = {}, related = {}},
        {
            severity = "warning",
            message = "bad location",
            range = {start = {}, ["end"] = {}},
            fixes = {},
            notes = {},
            related = {}
        },
    }) do
        local value = report()
        value.diagnostics = {diagnostic}
        test.eq(accepts(output(value)), false)
    end
    local value = report()
    value.diagnostics = {
        unexpected = {severity = "warning", message = "not an array", fixes = {}, notes = {}, related = {}}
    }
    test.eq(accepts(output(value)), false)
end

function M.preservesAndCountsOnlyTheKnownTypeFunctionCacheRejections()
    local path = "/checkout/build/self-build-core/cache/type-functions.buf"
    local native = "nupp: cannot save compiler cache "
        .. path
        .. ": runtime error: plain data must contain one non-executable root\n"
    local pure = "nupp: cannot save compiler cache " .. path .. ": plain data cannot contain a function\n"
    local printed = output():gsub(
        "built dist",
        function()
            return native .. pure .. "built dist"
        end,
        1
    )
    assert(accepts(printed))
    local warnings = validator.cacheWarnings(printed)
    test.eq(#warnings, 2)
    test.eq(warnings[1].path, path)
    test.eq(warnings[1].text .. "\n", native)
    test.eq(warnings[2].text .. "\n", pure)
    assert(accepts(native .. output() .. pure))
    assert(
        accepts(
            output():gsub(
                "1.123 compiler",
                function()
                    return native .. "1.123 compiler"
                end,
                1
            )
        )
    )
    for _, unknown in ipairs({
        native:gsub("type%-functions.buf", "checks.buf"),
        native:gsub("runtime error: plain data must contain one non%-executable root", "permission denied"),
        native:gsub("one non%-executable root", "one non-executable root and unexpected suffix"),
        (native:gsub("/checkout/build/self%-build%-core/cache/", "")),
    }) do
        test.eq(
            accepts(
                output():gsub(
                    "built dist",
                    function()
                        return unknown .. "built dist"
                    end,
                    1
                )
            ),
            false
        )
    end
end

function M.rejectsUnexpectedOutputInsteadOfDroppingIt()
    for _, line in ipairs({"nupp: cache warning", "error: bad compiler input", "  unknown progress text", ""}) do
        test.eq(accepts(output():gsub("built dist", line .. "\nbuilt dist", 1)), false)
    end
    test.eq(accepts(output():gsub('"ok":true', '"ok":invalid')), false)
    test.eq(accepts(output():gsub("1.123 compiler", "1.123 arbitrary\n1.123 compiler")), false)
end

function M.rejectsMissingRepeatedOrUnsuccessfulBoundaries()
    local valid = output()
    test.eq(accepts(valid:gsub("start core build", "start a different build")), false)
    test.eq(accepts(valid:gsub("status 0", "status 1")), false)
    test.eq(accepts(valid:gsub("1.123 compiler", "0.000 compiler")), true)
    test.eq(accepts(valid:gsub("0.000 compiler", "2.000 compiler", 1)), false)
    test.eq(accepts(valid:gsub("built dist in 1.0s: 2 compiled, 3 reused\n", "")), false)
    test.eq(accepts(valid:gsub("1.123 compiler", json.encodevalue(report()) .. "\n1.123 compiler")), false)
end

function M.rejectsProgressThatContradictsTheReport()
    local valid = output()
    for before, after in pairs({
        ["50%%"] = "99%",
        ["2 compiled"] = "4 compiled",
        ["1.0s"] = "5.0s",
        ["check 800ms"] = "unknown 800ms",
        ["main  800ms"] = "main  8ms",
    }) do
        test.eq(
            accepts(
                valid:gsub(before, function()
                    return after
                end)
            ),
            false
        )
    end
end

return M
