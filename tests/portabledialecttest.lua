local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local gen = require("nupp.compiler.gen")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

-- One environment for the whole suite.
--
-- Every case checks against an environment built exactly this way, and
-- building one means checking the prelude from source. Per case that was
-- most of what this suite cost; the cases share it the way the other
-- checker suites do.
local sharedEnv = envMod.new(HERE)
local ROOT = HERE == "tests" and "." or assert(HERE:match("^(.*)[/\\]tests$"))

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function read(path)
    local file = assert(io.open(path, "rb"))
    local contents = file:read("*a")
    file:close()
    return contents
end

local function checked(src, dialect)
    local result = parser.parse(src, "portable-test.g.nupp")
    assertEq(#result.errors, 0, "portable test source parses")
    local diags = check.check(result, "portable-test.g.nupp", sharedEnv, {dialect = dialect,})
    return result, diags
end

local M = {}

function M.recordTestsLowerForPortableAndCompatibilityDialects()
    local source = table.concat(
        {
            "local record Item",
            "   value: integer",
            "end",
            "local calls = 0",
            "local function subject(value: any): any",
            "   calls = calls + 1",
            "   return value",
            "end",
            "local function classify(value: Item | string | nil): boolean",
            "   return switch value do",
            "      case is Item -> true",
            "      else -> false",
            "   end",
            "end",
            "local item = new Item(value = 7)",
            "local yes = subject(item) is Item",
            "local no = subject(nil) is Item",
            "return yes, no, calls, classify(item), classify('empty'), classify(nil)",
        },
        "\n"
    )
    for _, dialect in ipairs({"lua51", "luajit-compat"}) do
        local result, diags = checked(source, dialect)
        assertEq(#diags, 0, "record tests check: " .. (diags[1] and diags[1].msg or ""))
        local code, loweringDiags = gen.generate(result, "portable-record.nupp")
        assertEq(#loweringDiags, 0, "record tests lower")
        assert(not code:find("?.", 1, true), "record tests must not retain native optional indexing")
        local chunk = assert(loadstring(code, "@portable-record"))
        local yes, no, calls, selected, empty, absent = chunk()
        assertEq(yes, true)
        assertEq(no, false)
        assertEq(calls, 2, "each tested subject is evaluated once")
        assertEq(selected, true)
        assertEq(empty, false)
        assertEq(absent, false)
    end
end

function M.realCorpusRunsUnderAvailableStockLuaAndLuaJIT()
    local command = ("'%s/scripts/portable-lua-corpus.sh' --available lua luajit 2>&1"):format(ROOT)
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    local ok, why, status = pipe:close()
    assert(ok, ("portable corpus failed (%s %s):\n%s"):format(tostring(why), tostring(status), output))
    assert(output:find("lua passed", 1, true) or output:find("lua unavailable", 1, true), output)
    assert(output:find("luajit passed", 1, true), output)

    local generated = read(ROOT .. "/tests/portable-corpus/build/main.lua")
    for _, spelling in ipairs({"?.", "??", "+=", "1_000", "|value"}) do
        assert(
            not generated:find(spelling, 1, true),
            "portable generated output retained " .. spelling .. ":\n" .. generated
        )
    end
    assert(not generated:match("%f[%a]const%f[^%w_]"), "portable generated output retained const:\n" .. generated)
    assert(
        generated:find("local unpack=unpack or table.unpack", 1, true),
        "portable output binds the moved unpack identity:\n" .. generated
    )
    assert(
        generated:find("local loadstring=loadstring or load", 1, true),
        "portable output binds the moved loadstring identity:\n" .. generated
    )
    assert(
        not generated:find('require("table.new")', 1, true),
        "portable table.new is a compiler lowering:\n" .. generated
    )
    assert(
        not generated:find('require("table.clear")', 1, true),
        "portable table.clear is a compiler lowering:\n" .. generated
    )
end

function M.explicitNativeDialectChangesNoGeneratedByte()
    local source = read(ROOT .. "/tests/portable-corpus/src/main.nupp")
    local default, defaultDiags = checked(source, nil)
    local native, nativeDiags = checked(source, "luajit")
    assertEq(#defaultDiags, 0, "default corpus checks")
    assertEq(#nativeDiags, 0, "explicit native corpus checks")
    assertEq(
        gen.generate(native, "native-corpus.nupp"),
        gen.generate(default, "native-corpus.nupp"),
        "explicit luajit output is byte-identical to the default"
    )
end

function M.compatibilityDialectLowersSyntaxAndRetainsLuaJITCapabilities()
    local source = table.concat(
        {
            "local struct Point",
            "    x: float",
            "end",
            "local point = new Point(1)",
            "point.x += 1",
            "return (point?.x ?? 0) & 3",
        },
        "\n"
    )
    local result, diags = checked(source, "luajit-compat")
    assertEq(#diags, 0, "compatibility output retains native LuaJIT capabilities")
    local code, loweringDiags = gen.generate(result, "compatibility.nupp")
    assertEq(#loweringDiags, 0, "compatibility source lowers")
    for _, spelling in ipairs({"?.", "??", "+=", " & "}) do
        assert(not code:find(spelling, 1, true), "compatibility output retained " .. spelling .. ":\n" .. code)
    end
    assert(code:find('require("ffi")', 1, true), "compatibility output retains LuaJIT FFI structs:\n" .. code)
    assert(
        code:find('require("bit")', 1, true) and code:find(".band(", 1, true),
        "compatibility output lowers operators through LuaJIT's BitOp module:\n" .. code
    )
end

function M.authoredJumpsAreRefusedOnlyByThePortableDialect()
    local source = table.concat({"local answer = 1", "goto done", "answer = 2", "::done::", "return answer",}, "\n")
    local _, nativeDiags = checked(source, "luajit")
    assertEq(#nativeDiags, 0, "LuaJIT retains authored jumps")
    local _, portableDiags = checked(source, "lua51")
    assertEq(#portableDiags, 2, "portable checking reports the label and goto")
    assertEq(portableDiags[1].code, "NUPP3009", "goto diagnostic code")
    assertEq(portableDiags[2].code, "NUPP3009", "label diagnostic code")
    assert(
        portableDiags[1].help:find("structured control flow", 1, true),
        "the refusal gives the structured alternative"
    )
end

function M.cdataNumeralsRequireRepresentationsThePortableDialectDoesNotHave()
    local _, nativeDiags = checked("return 1LL, 2ULL, 3i", "luajit")
    assertEq(#nativeDiags, 0, "LuaJIT retains cdata numerals")
    local _, portableDiags = checked("return 1LL, 2ULL, 3i", "lua51")
    assertEq(#portableDiags, 3, "each unportable cdata numeral is diagnosed")
    assert(portableDiags[1].msg:find("`int64` capability", 1, true), portableDiags[1].msg)
    assert(portableDiags[3].msg:find("`cinterop` capability", 1, true), portableDiags[3].msg)
end

function M.crossDialectOutputSkipsTheHostParserCheck()
    local result, diags = checked("return 2ULL", "luajit")
    assertEq(#diags, 0, "the LuaJIT-only source checks for its target")
    local code, loweringDiags = gen.generate(result, "native-from-portable.nupp", nil, nil, nil, "lua51")
    assertEq(#loweringDiags, 0, "a stock Lua 5.1 host does not reject LuaJIT output")
    assert(code:find("2ULL", 1, true), "LuaJIT-only output remains intact")
end

function M.runtimeSpecificPreludeUsesAreDefinitionBased()
    local source = table.concat(
        {
            "local values = {",
            "    setfenv, getfenv, package.loaders, bit, jit,",
            "    require(\"ffi\"), require(\"string.buffer\"), string.buffer,",
            "}",
            "local packageAlias = package",
            "values[#values + 1] = packageAlias.loaders",
            "return values",
        },
        "\n"
    )
    local _, nativeDiags = checked(source, "luajit")
    assertEq(#nativeDiags, 0, "LuaJIT retains its native prelude identities")
    local _, portableDiags = checked(source, "lua51")
    local identities = {}
    for _, diag in ipairs(portableDiags) do
        if diag.code == "NUPP3010" then
            identities[#identities + 1] = diag.msg
        end
    end
    assertEq(#identities, 9, "every runtime-specific resolved identity is diagnosed")
    assert(table.concat(identities, "\n"):find("package.loaders", 1, true), "the member identity is named")
    assert(table.concat(identities, "\n"):find("module `ffi`", 1, true), "the LuaJIT module is named")

    local shadowed = table.concat(
        {
            "local setfenv = 1",
            "local getfenv = 2",
            "local package = {loaders = 3}",
            "local bit = 4",
            "local jit = 5",
            "return setfenv + getfenv + package.loaders + bit + jit",
        },
        "\n"
    )
    local _, shadowedDiags = checked(shadowed, "lua51")
    for _, diag in ipairs(shadowedDiags) do
        assert(diag.code ~= "NUPP3010", "application definitions remain portable: " .. diag.msg)
    end
end

function M.portableCheckingStopsUnavailableRepresentationsBeforeGeneration()
    local cases = {
        {source = "local struct Point\n    x: number\nend\nreturn Point", capability = "structvalue"},
        {source = "local type Pointer = int32*\nreturn 1", capability = "cstorage"},
        {source = "cdef function read(value: int32): int32\nreturn read", capability = "cinterop"},
    }
    for _, case in ipairs(cases) do
        local _, nativeDiags = checked(case.source, "luajit")
        assertEq(#nativeDiags, 0, "LuaJIT retains native " .. case.capability)
        local _, portableDiags = checked(case.source, "lua51")
        local found = false
        for _, diag in ipairs(portableDiags) do
            found = found or diag.code == "NUPP3006" and diag.msg:find(
                "`" .. case.capability .. "` capability",
                1,
                true
            ) ~= nil
        end
        assert(found, "portable check reports missing " .. case.capability)
    end
end

function M.constErasureDoesNotRewriteStringContents()
    local result, diags = checked("const value = [[const field]]\nreturn value", "lua51")
    assertEq(#diags, 0, "portable string source checks")
    local code, loweringDiags = gen.generate(result, "portable-string.nupp")
    assertEq(#loweringDiags, 0, "portable string source lowers")
    assert(code:find("[[const field]]", 1, true), "const inside a long string is preserved:\n" .. code)
    local chunk, problem = loadstring(code, "@portable-string")
    assert(chunk, tostring(problem) .. "\n" .. code)
    assertEq(chunk(), "const field", "const string value")
end

function M.cleanupContinueAndBreakUseTheStructuredLoopExit()
    local source = table.concat(
        {
            "local h = {}",
            "local total = 0",
            "for index = 1, 3 do",
            "    handle suspension with h do",
            "        if index == 2 then continue end",
            "        total = total + index",
            "    end",
            "end",
            "while true do",
            "    handle suspension with h do",
            "        break",
            "    end",
            "end",
            "return total, true",
        },
        "\n"
    )
    local result, diags = checked(source, "lua51")
    for _, diag in ipairs(diags) do
        assert(
            diag.severity == "warning" or diag.severity == "note",
            "portable cleanup source checks: " .. diag.code .. " " .. diag.msg
        )
    end
    local code, loweringDiags = gen.generate(result, "portable-cleanup.nupp")
    assertEq(#loweringDiags, 0, "portable cleanup lowers cleanly")
    assert(
        not code:find("then continue", 1, true) and not code:find("\ncontinue", 1, true),
        "portable cleanup retained a continue statement:\n" .. code
    )
    assert(
        code:find("repeat", 1, true) and code:find('==\"break\"', 1, true),
        "portable loop uses a structured repeat and exit action:\n" .. code
    )
    local chunk, problem = loadstring(code, "@portable-cleanup")
    assert(chunk, "portable cleanup generated code loads: " .. tostring(problem) .. "\n" .. code)
    local continued, broken = chunk()
    assertEq(continued, 4, "cleanup continue reaches the authored loop")
    assertEq(broken, true, "cleanup break exits the authored loop")
end

function M.safeMemberReadsShareAHelperAndOperandsStayDeferred()
    -- `?.x` has nothing of its own to evaluate, so one module-level helper per
    -- member serves every site and a loop reading it builds no function. `?.[]`
    -- and `?.()` evaluate their key and arguments only once the receiver is present,
    -- as they do natively, so those keep a body of their own.
    local source = table.concat(
        {
            "local calls = 0",
            "local function key(): string",
            "   calls = calls + 1",
            "   return 'k'",
            "end",
            "local points: {any} = {{x = 2}, {}, {x = 3}}",
            "local none: any = nil",
            "local total = 0",
            "for index = 1, 3 do",
            "   total = total + (points[index]?.x ?? 0) + (none?.x ?? 0)",
            "end",
            "local absent: any = nil",
            "local missing: any = nil",
            "local byKey = absent?.[key()]",
            "local called = missing?.(key())",
            "return total, calls, byKey, called",
        },
        "\n"
    )
    local result, diags = checked(source, "lua51")
    assertEq(#diags, 0, "safe navigation source checks: " .. (diags[1] and diags[1].msg or ""))
    local code, loweringDiags = gen.generate(result, "portable-safe.nupp")
    assertEq(#loweringDiags, 0, "safe navigation lowers cleanly")
    assert(code:find("__nuppSafeIndex%d+%("), "member reads call a declared helper:\n" .. code)
    assertEq(select(2, code:gsub("return __nuppV%.x", "")), 1, "one helper serves the member:\n" .. code)
    local chunk, problem = loadstring(code, "@portable-safe")
    assert(chunk, "safe navigation generated code loads: " .. tostring(problem) .. "\n" .. code)
    local total, calls, byKey, called = chunk()
    assertEq(total, 5, "member reads through nil receivers")
    assertEq(calls, 0, "a key or argument is not evaluated for an absent receiver")
    assertEq(byKey, nil)
    assertEq(called, nil)
end

function M.wrappedRepeatLoopKeepsItsConditionInTheBodyScope()
    -- The wrapper's `until true` ends the body's scope, so the authored condition
    -- reads `done` inside it, and a `continue` reaches the condition the way it does
    -- natively rather than restarting the loop unconditionally.
    local source = table.concat(
        {
            "local i = 0",
            "local skipped = 0",
            "repeat",
            "    i = i + 1",
            "    local done = i >= 3",
            "    if i == 1 then",
            "        skipped = skipped + 1",
            "        continue",
            "    end",
            "until done",
            "local j = 0",
            "repeat",
            "    j = j + 1",
            "    local last = j == 2",
            "    if last then continue end",
            "until last",
            "return i, skipped, j",
        },
        "\n"
    )
    local result, diags = checked(source, "lua51")
    assertEq(#diags, 0, "portable repeat source checks: " .. (diags[1] and diags[1].msg or ""))
    local code, loweringDiags = gen.generate(result, "portable-repeat.nupp")
    assertEq(#loweringDiags, 0, "portable repeat lowers cleanly")
    assert(
        not code:find("until done", 1, true) and not code:find("until last", 1, true),
        "the authored condition is read outside the body's scope:\n" .. code
    )
    assert(
        select(2, code:gsub("=done;", "")) == 2,
        "the condition is evaluated at the body's end and at the continue:\n" .. code
    )
    local body = code:sub(assert(code:find("local i = 0", 1, true)), assert(code:find("return i ,", 1, true)))
    assertEq(select(2, body:gsub("\n", "")), 16, "the statement after the loops keeps its line:\n" .. body)
    local chunk, problem = loadstring(code, "@portable-repeat")
    assert(chunk, "portable repeat generated code loads: " .. tostring(problem) .. "\n" .. code)
    local i, skipped, j = chunk()
    assertEq(i, 3, "repeat stops when its condition holds")
    assertEq(skipped, 1, "continue skipped one iteration")
    assertEq(j, 2, "continue in a repeat loop re-evaluates the condition")
end

return M
