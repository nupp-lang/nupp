local G = require("nupp.compiler.vm.graph")
local clif = require("nupp.compiler.clif.graph")
local lower = require("nupp.compiler.clif.lower")
local fs = require("nupp.compiler.fs")
local ROOT = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/..")
local M = {}

local function rejects(call, fragment)
    local ok, problem = pcall(call)
    assert(not ok, "accepted invalid object leaf")
    assert(tostring(problem):find(fragment, 1, true), tostring(problem))
end

function M.leafReturnsKeepExactGraphValuesWithoutVmEntryArguments()
    local g = G.newNative({"uint64"}, "uint64", "leaf")
    local b, target = G.block(g), G.block(g)
    local transported, dead = G.nativeValue(g, "uint64"), G.nativeValue(g, "uint64")
    target.params = {transported, dead}
    b.term = {kind = "jump", edges = {{target = target.id, args = {1, 1}}}}
    target.term = {kind = "return", value = transported, edges = {}}
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(#target.params == 1 and g.native.frameFromWindow == nil and g.native.tableArgument == nil)
    local text = clif.emit(g, {name = "slotHash"})
    assert(text:find("function %slotHash(i64) -> i64 tail {", 1, true))
    assert(text:find("return v", 1, true))
    assert(not text:find("sig0", 1, true) and not text:find("return_call", 1, true))
    assert(not text:find("-32", 1, true))
end

function M.leavesCannotAcquireHandlerFramesOrCallManagedServices()
    local function fresh()
        local g = G.newNative({"voidptr", "voidptr", "voidptr", "voidptr", "voidptr", "voidptr"}, "uint64", "leaf")
        return g, G.block(g)
    end

    local g, b = fresh()
    b.term = {kind = "dispatch", args = {1, 2, 3, 4, 5, 6}, edges = {}}
    rejects(
        function()
            G.verify(g)
        end,
        "invalid native dispatch"
    )
    g, b = fresh()
    g.native.frameFromWindow = 2
    rejects(
        function()
            G.verify(g)
        end,
        "no VM entry transport"
    )
    g, b = fresh()
    local declaration = {
        moduleName = "nupp.runtime.vm.helpers",
        name = "pollCleanups",
        params = {"voidptr"},
        result = "nil",
        effects = {mayCollect = true, mayPark = true, mayRaise = true, pure = false}
    }
    G.emitNative(g, b, "NativeHelperCall", {declaration, 1}, nil)
    local answer = G.emitNative(g, b, "NativeConstant", {"0"}, "uint64")
    b.term = {kind = "return", value = answer, edges = {}}
    rejects(
        function()
            G.verify(g)
        end,
        "cannot access VM state or invoke managed helpers"
    )
    rejects(
        function()
            G.newNative({"number"}, "uint64", "leaf")
        end,
        "exact scalar kind"
    )
end

function M.canonicalSlotHashSourceUsesTheSharedGraphInOrdinaryNativeCompilation()
    local text = lower.compile(
        ROOT,
        {ROOT .. "/src/nupp/runtime/vm/values.nupp", ROOT .. "/src/nupp/runtime/vm/objecthash.nupp"},
        {include = {"src"}}
    )
    local body = assert(text:match("function %%slotHash%b()%s*%-%>%s*i64%s+tail%s*(%b{})"), text)
    assert(body:find("Nupp native graph: slotHash", 1, true), body)
    assert(body:find("imul", 1, true) and body:find("ushr", 1, true), body)
    assert(not body:find("call", 1, true), body)
end

return M
