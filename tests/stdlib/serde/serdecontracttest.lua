-- CLI smoke and the two Lua routes retired by the native rewrite.
local call = require("helpers.serdecontract").call
local json = require("testjson")
local process = require("nupp.compiler.process")
local fs = require("nupp.compiler.fs")
local HERE = require("helpers.paths").tests
local NUPP = fs.absolute(HERE .. "/../bin/nupp")
local PROJECT = fs.absolute(HERE .. "/../bench/serde-spike/contracts")
local M = {}

function M.externalMembersEraseBehindACheckedBinding()
    local status, output = call({
        "check",
        "--json",
        "erasure.nupp",
        "src/contract/dispatch.nupp",
        "src/contract/render.nupp",
        "src/example/model.nupp",
        "src/example/other.nupp"
    })
    assert(status == 0, output)
    local checked = json.decode(output)
    assert(checked.ok and #checked.diagnostics == 0, output)
    status, output = call({"run", "erasure.nupp"})
    assert(status == 0, output)
end

function M.compiledRecipesMatchVisitorAndRespectRefusals()
    local native = PROJECT .. "/native-build"
    local status, output = process.capture({NUPP, "build", "--target", "compiled-contracts", "--json"}, {cwd = native})
    assert(status == 0, output)
    local built = json.decode(output)
    assert(built.ok, output)
    status, output = process.capture({"luajit", PROJECT .. "/compiled_scope.lua"}, {
        cwd = native,
        env = {
            LUA_PATH = native .. "/build/?.lua;" .. fs.absolute(HERE .. "/../build") .. "/?.lua;" .. package.path,
            LUA_CPATH = package.cpath
        }
    })
    assert(status == 0, output)
end

function M.portableSourceProfileRejectsUnsupportedRuntimeDependencies()
    local status, output = call({"check", "--compat", "lua51", "--json", "negative/portable-profile.nupp"})
    assert(status ~= 0, output)
    local checked = json.decode(output)
    local rejected = false
    for _, diagnostic in ipairs(checked.diagnostics) do
        rejected = rejected
            or diagnostic.code == "NUPP3015"
            and diagnostic.message:find('module "serde" violates compatibility', 1, true)
    end
    assert(rejected, output)
end

return M
