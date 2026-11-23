-- The builtin closure harness (`builtinclosure.lua`) over a fixture builtin on the
-- pinned ISA-L CRC library, so the mechanism is proven before a C-backed builtin
-- of its own lands. Each library spec runs the same harness for its own entry.
--
-- Set NUPP_BUILTIN_CLOSURE_RECORD to a path to keep the run's package sizes.
local closure = require("tools.packaging.builtinclosure")

local FIXTURES = require("helpers.paths").absoluteTests .. "/tools/packaging/fixtures/builtinclosure"

local M = {}

function M.aFixtureBuiltinIsCarriedOnlyWhereItIsReached()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    local result = closure.run({
        name = "crcfixture",
        entry = {
            modules = {"crcfixture", "crcfixture.*"},
            owned = {},
            libraries = {
                {name = "nuppcrc", file = "nupp_crc", notices = {"ISA-L-LICENSE.txt", "ISA-L-CRC-LICENSE.txt"}},
            },
            hosts = {"native"},
        },
        hello = FIXTURES .. "/hello",
        uses = FIXTURES .. "/uses",
        reaches = {"crcfixture"},
        chain = {"src/main.nupp", "src/app/checksum.nupp"},
        record = os.getenv("NUPP_BUILTIN_CLOSURE_RECORD"),
    })
    assert(#result.problems == 0, "the closure harness found:\n  " .. table.concat(result.problems, "\n  "))
    assert(result.sizes.uses > result.sizes.hello, "uses carries more than hello")
    io.stderr:write(
        ("builtin closure: hello %d bytes, uses %d bytes, crcfixture %d bytes\n"):format(
            result.sizes.hello,
            result.sizes.uses,
            result.sizes.difference
        )
    )
end

-- serde.xml is a builtin with no C library: a program that does not reach it,
-- serde.json's included, carries none of its modules, and one that does carries
-- them and is refused when built --without xml.
function M.xmlIsCarriedOnlyWhereItIsReached()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    for _, hello in ipairs({FIXTURES .. "/hello", FIXTURES .. "/xmlhellojson"}) do
        local result = closure.run({
            name = "xml",
            hello = hello,
            uses = FIXTURES .. "/xmluses",
            reaches = {"serde.xml", "serde.xml.internal.cursor", "serde.xml.internal.tree"},
            chain = {"src/main.nupp", "src/app/feed.nupp"},
            record = os.getenv("NUPP_BUILTIN_CLOSURE_RECORD"),
        })
        assert(#result.problems == 0, "the closure harness found:\n  " .. table.concat(result.problems, "\n  "))
        assert(result.sizes.uses > result.sizes.hello, "uses carries more than hello")
        io.stderr:write(
            ("builtin closure: %s %d bytes, xml uses %d bytes, serde.xml %d bytes\n"):format(
                hello:match("([^/]+)$"),
                result.sizes.hello,
                result.sizes.uses,
                result.sizes.difference
            )
        )
    end
end

return M
