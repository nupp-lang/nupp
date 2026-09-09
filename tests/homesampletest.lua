-- The home page's code samples, held to the compiler that claims them.
--
-- Every other example in the project is checked by something: the reference
-- chapters by referencetest, the documentation site by doctest. The home page's
-- feature cards were the one place a sample could stop compiling in silence,
-- which is the most expensive place to be wrong, since it is the first Nupp
-- most readers ever see.
--
-- A card is a fragment rather than a program, so each is checked as `.g.nupp`:
-- the strict floor would demand context a card deliberately leaves out, while
-- gradual checking still resolves every name the card does spell out. Warnings
-- are allowed for the same reason -- a card declares things to show the syntax
-- and is not obliged to use them.

local json = require("testjson")
local home = require("nupp.compiler.doc.home")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = HERE .. "/.."
local NUPP = ROOT .. "/bin/nupp"

local M = {}

function M.crlfFencesKeepTheirLanguage()
    local parsed = home.features(
        table.concat(
            {
                "## Portable",
                "",
                "The checkout decides its line endings.",
                "",
                "```nupp",
                "local answer: number = 42",
                "```",
            },
            "\r\n"
        )
    )

    assert(#parsed == 1)
    assert(parsed[1].codeLanguage == "nupp", parsed[1].codeLanguage)
    assert(parsed[1].code == "local answer: number = 42", parsed[1].code)
end

--- The home page's feature cards, read from the page they are written on.
local function features()
    local file = assert(io.open(ROOT .. "/docs/index.md", "rb"), "the home page")
    local markdown = file:read("*a")
    file:close()

    return assert(home.parse(markdown).features, "the home page's features")
end

--- Every card's sample, checked together in one project.
---
--- A card was checked in a project of its own, which meant a compiler start and
--- a project graph per sample for a file that declares nothing. The samples
--- cannot collide -- each is a `.g.nupp` naming no module -- so one project
--- holding all of them answers the same question in one invocation.
---
--- The file a diagnostic names is what says which card reported it, so the
--- failure still points at a card rather than at the batch.
local function diagnosticsByCard(cards)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
    manifest:write('return {include = {"."}}\n')
    manifest:close()
    local names = {}
    for index, card in ipairs(cards) do
        local name = ("sample%d.g.nupp"):format(index)
        names[index] = name
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(card.code .. "\n")
        file:close()
    end
    local pipe = assert(
        io.popen(("cd '%s' && '%s' check --json %s 2>/dev/null"):format(dir, NUPP, table.concat(names, " ")))
    )
    local out = pipe:read("*a")
    pipe:close()
    os.execute("rm -rf '" .. dir .. "'")
    local ok, decoded = pcall(json.decode, out)
    assert(ok, "check --json did not produce JSON: " .. out)
    local byCard = {}
    for index = 1, #cards do
        byCard[index] = {}
    end
    for _, diagnostic in ipairs(decoded.diagnostics or {}) do
        local file = tostring(diagnostic.file or "")
        local index = tonumber(file:match("sample(%d+)%.g%.nupp$"))
        assert(
            index,
            ("a diagnostic came from %q, which is no card's sample: %s"):format(file, diagnostic.message or "?")
        )
        local found = byCard[index]
        found[#found + 1] = diagnostic
    end

    return byCard
end

function M.everyHomePageSampleChecks()
    local cards = {}
    for index, feature in ipairs(features()) do
        if feature.code and (feature.codeLanguage or "nupp") == "nupp" then
            cards[#cards + 1] = {title = feature.title or index, code = feature.code}
        end
    end
    assert(#cards >= 5, "expected the home page to carry five samples")
    for index, diagnostics in ipairs(diagnosticsByCard(cards)) do
        local card = cards[index]
        for _, diagnostic in ipairs(diagnostics) do
            if diagnostic.severity == "error" then
                error(
                    (
                        "the %q sample reports %s: %s\n%s"
                    ):format(card.title, diagnostic.code or "?", diagnostic.message or "", card.code),
                    2
                )
            end
        end
    end
end

return M
