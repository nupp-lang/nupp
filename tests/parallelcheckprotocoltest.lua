local protocol = require("nupp.tools.build.parallelcheckprotocol")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function request()
    return {
        schema = 1,
        kind = "check",
        requestId = 7,
        sessionKey = "compiler\0config",
        paths = {"src/a.nupp"},
        exportPaths = {"src/a.nupp"},
        sources = {{path = "src/a.nupp", hash = "source-a", name = "a", supported = true}},
        imports = {
            {
                path = "/tmp/interface.buf",
                fingerprint = "interface-b",
                transportFingerprint = "transport-b",
            },
        },
        declaredModules = {a = true},
        supportedModules = {a = true},
    }
end

local M = {}

function M.roundTripsBinaryPayloadsAndFrames()
    local value = {bytes = "before\0after\255\\xFF", list = {"a", "b", "c"}, nested = {answer = 42, enabled = true},}
    local encoded = protocol.encode(value)
    local decoded, problem = protocol.decode(encoded)
    assert(decoded, problem)
    assertEq(decoded.bytes, value.bytes, "binary string")
    assertEq(decoded.list[3], "c", "array member")
    assertEq(decoded.nested.answer, 42, "nested member")
    assertEq(protocol.frame(value), tostring(#encoded) .. "\n" .. encoded, "length-delimited frame")
end

function M.fingerprintsEveryImmutableRequestInput()
    local original = request()
    local expected = protocol.requestFingerprint(original)
    assertEq(protocol.requestFingerprint(request()), expected, "stable request fingerprint")

    local mutations = {
        function(value)
            value.requestId = 8
        end,
        function(value)
            value.kind = "scan"
        end,
        function(value)
            value.sessionKey = "other"
        end,
        function(value)
            value.paths[1] = "src/b.nupp"
        end,
        function(value)
            value.exportPaths = {}
        end,
        function(value)
            value.sources[1].hash = "changed"
        end,
        function(value)
            value.sources[1].name = "b"
        end,
        function(value)
            value.sources[1].supported = false
        end,
        function(value)
            value.imports[1].fingerprint = "changed"
        end,
        function(value)
            value.imports[1].path = "/tmp/other.buf"
        end,
        function(value)
            value.imports[1].transportFingerprint = "changed"
        end,
        function(value)
            value.declaredModules.b = true
        end,
        function(value)
            value.supportedModules.a = false
        end,
    }
    for position, mutate in ipairs(mutations) do
        local changed = request()
        mutate(changed)
        assert(protocol.requestFingerprint(changed) ~= expected, "mutation " .. position .. " changed the fingerprint")
    end
end

function M.rejectsMalformedPayloads()
    local decoded, problem = protocol.decode("Bnot-a-buffer")
    assertEq(decoded, nil, "malformed binary payload")
    assert(problem:find("malformed", 1, true), problem)

    decoded, problem = protocol.decode("J42")
    assertEq(decoded, nil, "non-object payload")
    assert(problem:find("object", 1, true), problem)
end

return M
