-- How the YAML encoder writes a scalar (serde.yaml.internal.style): a string
-- is plain only when it reads back as itself under the 1.2 core schema and
-- YAML 1.1, and a float's text is the shortest that reads back as it.
local resolve = require("serde.yaml.internal.resolve")
local style = require("serde.yaml.internal.style")
local test = require("assert")
local M = {}

function M.ordinaryWordsArePlain()
    for _, text in ipairs({"watchashow", "hello world", "a-b", "path/to/file", "x:y", "v1.2", "email@example.com", "a#b"}) do
        test(style.plain(text), text)
    end
end

function M.anythingEitherSchemaReadsOtherwiseIsQuoted()
    local ambiguous = {
        "",
        "~",
        "null",
        "true",
        "False",
        "yes",
        "No",
        "on",
        "OFF",
        "y",
        "n",
        "<<",
        "=",
        "1",
        "-1",
        "+1",
        "1.5",
        ".5",
        "1e3",
        ".inf",
        "-.inf",
        ".nan",
        "0x1F",
        "0o7",
        "0b101",
        "1_000",
        "190:20:30",
        "2026-11-20",
        "2026-11-20T12:00:00Z",
    }
    for _, text in ipairs(ambiguous) do
        test(not style.plain(text), text)
    end
end

function M.indicatorsSpacesAndControlsAreQuoted()
    local awkward = {
        " lead",
        "trail ",
        "-dash",
        "?q",
        ":colon",
        "#hash",
        "&anchor",
        "*alias",
        "!tag",
        "|pipe",
        ">fold",
        "'single",
        "\"double",
        "%percent",
        "@at",
        "`tick",
        "[flow",
        "{flow",
        "a, b",
        "a]",
        "key: value",
        "note #comment",
        "ends:",
        "line\nbreak",
        "tab\there",
        "nul\0byte",
        "caf\195\169",
    }
    for _, text in ipairs(awkward) do
        test(not style.plain(text), text)
    end
end

function M.everyPlainStringResolvesToItself()
    local candidates = {"abc", "a b c", "x1", "under_score", "CamelCase", "dot.ted", "slash/ed", "tilde~", "q?mark"}
    for _, text in ipairs(candidates) do
        if style.plain(text) then
            local kind, value = resolve.plain(text)
            test(kind == "string" and value == text, text)
        end
    end
end

function M.floatTextIsShortestAndReadsBackAsAFloat()
    local cases = {
        [1.0] = "1.0",
        [-2.0] = "-2.0",
        [0.1] = "0.1",
        [1.5] = "1.5",
        [1e20] = "1.0e+20",
        [1.25e-7] = "1.25e-07",
        [123456789.125] = "123456789.125",
    }
    for value, expected in pairs(cases) do
        local text = style.float(value)
        test(text == expected, text)
        local kind, back = resolve.plain(text)
        test(kind == "float" and back == value, text)
    end
    test(style.float(math.huge) == ".inf")
    test(style.float(-math.huge) == "-.inf")
    test(style.float(0.0 / 0.0) == ".nan")
    for _, value in ipairs({math.pi, 1 / 3, 2 ^ 60 + 0.0, 5e-324, 1.7976931348623157e308}) do
        local kind, back = resolve.plain(style.float(value))
        test(kind == "float" and back == value, style.float(value))
    end
end

return M
