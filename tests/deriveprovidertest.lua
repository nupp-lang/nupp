-- End-to-end coverage for public and compiler-shipped comptime providers.

local process = require("nupp.compiler.build.process")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local NUPP = HERE .. "/../bin/nupp"

local M = {}
function M.runsThePublicComptimeForwardingRecipeEndToEnd()
    local consumer = HERE .. "/fixtures/deriveinspect_consumer.nupp"
    local checked, checkOutput = process.capture({NUPP, "check", "--strict", consumer})
    assert(checked == 0, checkOutput)
    local ran, runOutput = process.capture({NUPP, "run", consumer})
    assert(ran == 0, runOutput)

    local localProvider = HERE .. "/fixtures/derivelocal.nupp"
    local ranLocal, localOutput = process.capture({NUPP, "run", localProvider})
    assert(ranLocal == 0, localOutput)

    local invalid = HERE .. "/fixtures/deriveinspect_invalid.nupp"
    local rejected, rejection = process.capture({NUPP, "check", invalid})
    assert(rejected ~= 0, "unsupported provider input was accepted")
    assert(rejection:find("NUPP2810", 1, true), rejection)
    assert(rejection:find("unsupported", 1, true), rejection)

    local invalidProvider = HERE .. "/fixtures/deriveinvalidprovider.nupp"
    local refused, refusal = process.capture({NUPP, "check", invalidProvider})
    assert(refused ~= 0, "invalid provider declarations were accepted")
    assert(refusal:find("NUPP2809", 1, true), refusal)

    local immutable = HERE .. "/fixtures/deriveimmutable.nupp"
    local mutated, mutation = process.capture({NUPP, "check", immutable})
    assert(mutated ~= 0, "a provider mutated its Info projection")
    assert(mutation:find("cannot be assigned through", 1, true), mutation)
end

return M
