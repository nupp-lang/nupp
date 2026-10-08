local testAssert = require("nupp.test")
-- Exhaustiveness: a chain that dispatches on a union of literals and leaves
-- through every branch is claiming to handle every member.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function diagsOf(src)
    local result = parser.parse(src, "test.g.nupp")
    testAssert.equal(#result.errors, 0, "syntax: " .. (result.errors[1] and result.errors[1].msg or ""))
    local out = {}
    for j, d in ipairs(check.check(result, "test.g.nupp", env)) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

local function messageOf(src)
    local result = parser.parse(src, "test.g.nupp")
    local d = check.check(result, "test.g.nupp", env)[1]
    return d and d.msg or ""
end

local COLOR = "local type Color = 'red' | 'green' | 'blue'"

local M = {}

-- A branch that cannot produce a value adds no member to the value's type, so a
-- ternary with a failing arm still dispatches over the literal union.
function M.aFailingArmDoesNotHideTheDispatch()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local type Mode = 'a' | 'b' | 'c'",
                    "local function fail(msg: string): never error(msg) end",
                    "local function f(m: Mode, ok: boolean): integer",
                    "   local c = ok ? m : fail('no')",
                    "   if c == 'a' then return 1",
                    "   elseif c == 'b' then return 2",
                    "   end",
                    "   return 0",
                    "end",
                    "return f",
                },
                "\n"
            )
        ),
        "NUPP2107"
    )
end

function M.aDispatchMissingAMemberIsReported()
    local src = COLOR .. table.concat(
        {
            "",
            "local function name(c: Color): string",
            "    if c == 'red' then",
            "        return 'r'",
            "    elseif c == 'green' then",
            "        return 'g'",
            "    end",
            "end",
        },
        "\n"
    )
    testAssert.equal(diagsOf(src), "NUPP2107")
    local msg = messageOf(src)
    assert(msg:find('"blue"', 1, true), "names the member: " .. msg)
    assert(msg:find('"green"', 1, true), "names the set: " .. msg)
end

function M.everyMissingMemberIsNamed()
    local msg = messageOf(
        COLOR .. table.concat(
            {
                "",
                "local function name(c: Color): string",
                "    if c == 'red' then",
                "        return 'r'",
                "    end",
                "end",
            },
            "\n"
        )
    )
    assert(msg:find('"blue"', 1, true) and msg:find('"green"', 1, true), "both remaining members: " .. msg)
end

function M.aCompleteDispatchIsSilent()
    testAssert.equal(
        diagsOf(
            COLOR .. table.concat(
                {
                    "",
                    "local function name(c: Color): string",
                    "    if c == 'red' then",
                    "        return 'r'",
                    "    elseif c == 'green' then",
                    "        return 'g'",
                    "    elseif c == 'blue' then",
                    "        return 'b'",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        ""
    )
end

function M.partialHandlingIsNotADispatch()
    -- the branch does not leave, so the chain is not claiming to be total
    testAssert.equal(
        diagsOf(
            COLOR .. table.concat(
                {
                    "",
                    "local function paint(c: Color): nil",
                    "    if c == 'red' then",
                    "        print('red!')",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        ""
    )
end

function M.anElseBranchCoversTheRest()
    testAssert.equal(
        diagsOf(
            COLOR .. table.concat(
                {
                    "",
                    "local function name(c: Color): string",
                    "    if c == 'red' then",
                    "        return 'r'",
                    "    else",
                    "        return '?'",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        ""
    )
end

function M.errorCountsAsLeaving()
    testAssert.equal(
        diagsOf(
            COLOR .. table.concat(
                {
                    "",
                    "local function name(c: Color): string",
                    "    if c == 'red' then",
                    "        return 'r'",
                    "    elseif c == 'green' then",
                    "        error('no')",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2107",
        "a raising branch still leaves"
    )
end

function M.chainsOverDifferentSubjectsAreLeftAlone()
    testAssert.equal(
        diagsOf(
            COLOR .. table.concat(
                {
                    "",
                    "local function pick(a: Color, b: Color): string?",
                    "    if a == 'red' then",
                    "        return 'a'",
                    "    elseif b == 'green' then",
                    "        return 'b'",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        ""
    )
end

function M.nonEnumChainsAreUnaffected()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function f(s: string): string?",
                    "    if s == 'a' then",
                    "        return '1'",
                    "    elseif s == 'b' then",
                    "        return '2'",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        "",
        "an open type has no members to exhaust"
    )
end

function M.theRemainingMembersNarrowInLaterBranches()
    -- subtraction composes, so a later branch sees only what is left
    testAssert.equal(
        diagsOf(
            COLOR .. table.concat(
                {"", "local c: Color", "if c == 'red' then", "else", "    local still: Color = c", "end",},
                "\n"
            )
        ),
        ""
    )
end

return M
