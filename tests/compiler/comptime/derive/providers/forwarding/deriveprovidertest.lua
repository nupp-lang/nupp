local fixture = require("helpers.deriveprovider")
local HERE = fixture.HERE
local STRICT = fixture.STRICT
local REFUSED = fixture.REFUSED
local checksStrictly = fixture.checksStrictly
local refuses = fixture.refuses
local ran = fixture.ran

local M = {}

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

return M
