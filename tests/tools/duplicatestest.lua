local duplicates = require("nupp.tools.duplicates")
local M = {}

local function audit(texts, options)
    local sources = {}
    for file, text in pairs(texts) do
        sources[#sources + 1] = {file = file, text = text}
    end
    options = options or {minTokens = 10, minLines = 2}
    local report = duplicates.scan(sources, options)
    assert(report.ok, report.diagnostics[1] and report.diagnostics[1].message)

    return report
end

local BODY = "local total = value + 1\nlocal twice = total * 2\nreturn twice\n"

local function fn(name, body, parameter)
    return "local function " .. name .. "(" .. (parameter or "value") .. ")\n" .. body .. "end\n"
end

function M.matchesWholeFunctionsAcrossFilesAndIgnoresTrivia()
    local report = audit({
        ["a.nupp"] = fn("first", BODY),
        ["b.nupp"] = fn("second", "-- comment\n" .. (BODY:gsub(" = ", "=")))
    })
    assert(#report.groups == 1)
    local group = report.groups[1]
    assert(#group.occurrences == 2)
    assert(group.occurrences[1].kind == "function")
    assert(group.occurrences[1].functionName == "first")
    assert(group.occurrences[1].range.start.line == 2)
    assert(group.snippet == BODY:sub(1, -2))
end

function M.renamesLocalsConsistentlyButExactModeKeepsNames()
    local other = BODY:gsub("value", "input"):gsub("total", "sum"):gsub("twice", "result")
    local sources = {["a.nupp"] = fn("first", BODY), ["b.nupp"] = fn("second", other, "input")}
    assert(#audit(sources).groups == 1)
    assert(#audit(sources, {mode = "exact", minTokens = 10, minLines = 2}).groups == 0)
    local inconsistent = "local sum = input + 1\nlocal result = input * 2\nreturn result\n"
    assert(#audit({["a.nupp"] = fn("first", BODY), ["b.nupp"] = fn("second", inconsistent, "input")}).groups == 0)
end

function M.findsSectionsInsideDifferentLargerFunctions()
    local report = audit({
        ["a.nupp"] = fn("first", 'print("first")\n' .. BODY),
        ["b.nupp"] = fn("second", 'warn("second")\n' .. BODY),
    })
    assert(#report.groups == 1)
    assert(report.groups[1].occurrences[1].kind == "block")
    assert(report.groups[1].occurrences[1].range.start.line == 3)
end

function M.keepsMembersGlobalsTypesAndLiteralValues()
    local body = 'local result: string = api.read(value)\nreturn result .. "suffix"\n'
    for _, other in ipairs({
        body:gsub("read", "write"),
        body:gsub("api", "other"),
        body:gsub("string", "number"),
        (body:gsub("suffix", "prefix"))
    }) do
        assert(#audit({["a.nupp"] = fn("first", body), ["b.nupp"] = fn("second", other)}).groups == 0)
    end
    assert(
        #audit({["a.nupp"] = fn("first", body), ["b.nupp"] = fn("second", (body:gsub("suffix", "prefix")))}, {
            minTokens = 10,
            minLines = 2,
            ignoreLiterals = true
        }).groups == 1
    )
end

function M.respectsShadowedBindingsAndInitializerScope()
    local left = "local x = value\ndo\nlocal x = x + 1\nprint(x, value)\nend\nreturn x\n"
    local right = "local outer = input\ndo\nlocal inner = outer + 1\nprint(inner, input)\nend\nreturn outer\n"
    local report = audit({["a.nupp"] = fn("first", left), ["b.nupp"] = fn("second", right, "input")})
    assert(#report.groups == 1 and report.groups[1].occurrences[1].kind == "function")
    right = right:gsub("return outer", "return input")
    report = audit({["a.nupp"] = fn("first", left), ["b.nupp"] = fn("second", right, "input")})
    assert(report.groups[1].occurrences[1].kind == "block")
    assert(report.groups[1].snippet:find("return", 1, true) == nil)
end

function M.includesThirdCopiesWhenTwoShareALongerPrefix()
    local common = "local total = value + 1\nlocal twice = total * 2\n"
    local report = audit({
        ["a.nupp"] = fn("first", common .. "return twice\n"),
        ["b.nupp"] = fn("second", common .. "return twice\n"),
        ["c.nupp"] = fn("third", common .. 'print("other")\n')
    })
    assert(#report.groups == 2)
    assert(#report.groups[1].occurrences == 2)
    assert(#report.groups[2].occurrences == 3)
end

function M.findsSeparateCopiesInOneFile()
    local report = audit({["a.nupp"] = fn("first", BODY) .. fn("second", BODY)})
    assert(#report.groups == 1 and #report.groups[1].occurrences == 2)
    local a, b = unpack(report.groups[1].occurrences)
    assert(a.range["end"].offset < b.range.start.offset)
end

function M.neverJoinsIncompleteStatementsOrDifferentFunctionBodies()
    local report = audit({
        ["a.nupp"] = fn("first", "return value + 1\n") .. fn("second", "return value * 2\n"),
        ["b.nupp"] = fn("third", "return value + 1\n") .. fn("fourth", "return value * 2\n")
    })
    assert(#report.groups == 0)
end

function M.countsCodeLinesWithoutPaddingFromComments()
    local body = "local x = value + 1 -- comment\n\n-- more comment\n\nreturn x * 2\n"
    assert(
        #audit({["a.nupp"] = fn("first", body), ["b.nupp"] = fn("second", body)}, {
            minTokens = 10,
            minLines = 3
        }).groups == 0
    )
end

function M.reportsUnreadableAndInvalidSourcesWithoutHidingValidMatches()
    local report = duplicates.scan(
        {
            {file = "a.nupp", text = fn("first", BODY)},
            {file = "b.nupp", text = fn("second", BODY)},
            {file = "bad.nupp", text = "local function("},
            {file = "missing.nupp", error = "missing file"}
        },
        {minTokens = 10, minLines = 2}
    )
    assert(not report.ok and not report.complete)
    assert(report.filesScanned == 2 and #report.groups == 1)
    assert(#report.diagnostics >= 2)
end

function M.budgetAndOutputLimitAreExplicit()
    local sources = {{file = "a.nupp", text = fn("first", BODY)}, {file = "b.nupp", text = fn("second", BODY)}}
    local report = duplicates.scan(sources, {budget = 1})
    assert(not report.ok and not report.complete)
    assert(report.diagnostics[1].message:find("budget", 1, true))
    local common = "local total = value + 1\nlocal twice = total * 2\n"
    report = audit(
        {
            ["a.nupp"] = fn("first", common .. "return twice\n"),
            ["b.nupp"] = fn("second", common .. "return twice\n"),
            ["c.nupp"] = fn("third", common .. 'print("other")\n')
        },
        {minTokens = 10, minLines = 2, maxGroups = 1}
    )
    assert(report.complete and report.truncated and #report.groups == 1)
end

function M.cancellationEscapesTheAudit()
    local cancelled = {}
    local ok, err = pcall(duplicates.scan, {{file = "a.nupp", text = fn("first", BODY)}}, {}, function()
        error(cancelled)
    end)
    assert(not ok and err == cancelled)
end

function M.deduplicatesPathsAndOrdersResultsDeterministically()
    local a, b = {file = "a.nupp", text = fn("first", BODY)}, {file = "b.nupp", text = fn("second", BODY)}
    local options = {minTokens = 10, minLines = 2}
    local left, right = duplicates.scan({b, a, a}, options), duplicates.scan({a, b}, options)
    assert(left.filesScanned == 2)
    assert(require("testjson").encode(left) == require("testjson").encode(right))
end

function M.manyIdenticalFunctionsDoNotRequireAllPairs()
    local sources = {}
    for i = 1, 100 do
        sources[i] = {file = string.format("%03d.nupp", i), text = fn("copy" .. i, BODY)}
    end
    local report = duplicates.scan(sources, {minTokens = 10, minLines = 2, budget = 100000})
    assert(report.complete, "repeated functions must stay within the linearithmic search budget")
    assert(#report.groups == 1 and #report.groups[1].occurrences == 100)
end

function M.findsRepeatedInterfaceMembersDespiteDifferentTypeNames()
    local members = "read: function(self, count: integer): string\nclose: function(self): boolean\n"
    local report = audit({
        ["a.nupp"] = "interface Reader\n" .. members .. "end\n",
        ["b.nupp"] = "interface Source\n" .. members .. "end\n"
    })
    assert(#report.groups == 1)
    assert(report.groups[1].occurrences[1].kind == "members")
    assert(report.groups[1].occurrences[1].declarationName == "Reader")
end

function M.repeatConditionsSeeTheirBodyLocals()
    local a = "repeat\nlocal x = value + 1\nprint(x)\nuntil x > 10\nreturn value\n"
    local b = "repeat\nlocal y = input + 1\nprint(y)\nuntil y > 10\nreturn input\n"
    local report = audit({["a.nupp"] = fn("first", a), ["b.nupp"] = fn("second", b, "input")})
    assert(report.groups[1].occurrences[1].kind == "function")
end

function M.rejectsMalformedOptions()
    for _, options in ipairs({false, "wrong", {minLines = false}, {ignoreLiterals = 1}, {mode = "fuzzy"}}) do
        local value, reason = duplicates.options(options)
        assert(not value and reason)
    end
end

function M.snippetLimitPreservesMultibyteCharacters()
    local body = 'return "' .. string.rep("x", 1991) .. '😀tail"\n'
    local report = audit({["a.nupp"] = fn("first", body), ["b.nupp"] = fn("second", body)}, {
        minTokens = 2,
        minLines = 1
    })
    assert(report.groups[1].snippetTruncated)
    assert(#report.groups[1].snippet == 1999)
    assert(report.groups[1].snippet == body:sub(1, 1999))
end

return M
