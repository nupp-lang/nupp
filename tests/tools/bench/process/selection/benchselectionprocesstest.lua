local fixture = require("helpers.benchprocess")
local testAssert = fixture.testAssert
local HERE = fixture.HERE
local NUPP = fixture.NUPP
local TIMEOUT_MS = fixture.TIMEOUT_MS
local read = fixture.read
local workspace = fixture.workspace
local inWorkspace = fixture.inWorkspace

local M = {}

-- Each selector has to actually select.
--
-- `--case` silently did nothing for a while: the command record names the field
-- `caseGmatch` so the option can be spelled `--case`, and the code read `values.case`,
-- which is always nil. The pattern was validated and then ignored, so a run narrowed
-- to one case quietly measured every case in the file and said nothing. A filter that
-- accepts its argument and discards it is worse than one that rejects it, so each
-- dimension is asserted on its own rather than in combination, where another
-- dimension's filtering can cover for it.
function M.eachSelectorNarrowsOnItsOwn()
    local working = workspace()
    local stdout = working .. "/stdout.txt"
    local fixture = HERE .. "/fixtures/bench_suite.nupp"

    local function listed(...)
        local flags = table.concat({...}, " ")
        testAssert.eq(
            os.execute(
                inWorkspace(
                    working,
                    (
                        "%q bench --timeout-ms " .. TIMEOUT_MS .. " --list --file %q %s > %q"
                    ):format(NUPP, fixture, flags, stdout)
                )
            ),
            0,
            "listing with " .. flags .. " exits successfully"
        )
        -- The heading row is dropped rather than counted: the listing is a table now,
        -- and every count below is a count of benchmarks.
        local names = {}
        for line in read(stdout):gmatch("[^\r\n]+") do
            local name = line:match("^(%S+)")
            if name ~= "benchmark" then
                names[#names + 1] = name
            end
        end

        return names
    end

    local everything = listed()
    assert(#everything > 1, "the fixture defines more than one benchmark to narrow from")

    -- Every benchmark in this fixture is the same case, so a matching pattern
    -- correctly selects all of them and cannot show that the filter ran. A pattern
    -- matching nothing can: if `--case` were being discarded again, this would list
    -- the whole file and exit zero.
    -- Not compared against a number: `os.execute` hands back the raw wait status here,
    -- so a failing exit reads as 256 rather than 1 and the encoding is not portable.
    assert(
        os.execute(
            inWorkspace(
                working,
                (
                    "%q bench --timeout-ms " .. TIMEOUT_MS .. " --list --file %q --case %q > %q 2>&1"
                ):format(NUPP, fixture, "^nosuchcase$", stdout)
            )
        ) ~= 0,
        "a case pattern matching nothing selects nothing rather than everything"
    )
    assert(read(stdout):find("no benchmark matched") ~= nil, "and says so")

    local byCase = listed("--case", "'^work$'")
    testAssert.eq(#byCase, #everything, "every benchmark here is that case, so all of them match")

    local byVariant = listed("--variant", "'^base$'")
    assert(#byVariant > 0, "--variant selects something")
    assert(#byVariant < #everything, "--variant narrows")
    for _, name in ipairs(byVariant) do
        assert(name:find("%.base") ~= nil, "--variant selected " .. name .. ", which is not that variant")
    end

    local byParameter = listed("--parameter", "'^size=1$'")
    assert(#byParameter > 0, "--parameter selects something")
    assert(#byParameter < #everything, "--parameter narrows")
    for _, name in ipairs(byParameter) do
        assert(name:find("size=1$") ~= nil, "--parameter selected " .. name .. ", which is not that parameter")
    end

    os.execute(("rm -rf %q"):format(working))
end

return M
