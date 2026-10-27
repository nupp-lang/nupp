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

function M.nativeLayoutConstantsComeFromCheckedNuppTypes()
    local path = fs.absolute(os.tmpname() .. ".nupp")
    local source = [[
module nupp.runtime.vm.objecthash
const native = require("nupp.runtime.vm.intrinsics")
local struct Payload
    head: uint8
    word: uint64
end
local type Alias = Payload
local type Pointer = Payload*
export function slotHash(unused: uint64): uint64
    return native.sizeOf<Alias>() + native.alignmentOf<Alias>() + native.word(native.fieldOffset<Alias>("word"))
end
local function ordinary(): uint64
    return native.sizeOf<Alias>() + native.alignmentOf<Alias>() + native.word(native.fieldOffset<Alias>("word"))
end
local function pointerLayout(): uint64
    return native.sizeOf<Pointer>() + native.alignmentOf<Pointer>()
end
]]
    assert(fs.writeFile(path, source))
    local ok, text = pcall(lower.compile, ROOT, {path}, {include = {"src"}})
    os.remove(path)
    assert(ok, tostring(text))
    for _, name in ipairs({"slotHash", "ordinary"}) do
        local body = assert(text:match("function %%" .. name .. "%b()%s*%-%>%s*i64%s*[^\n{]*(%b{})"), text)
        assert(body:find("iconst.i64 16", 1, true) and body:find("iconst.i64 8", 1, true), body)
        assert(not body:find("call", 1, true), body)
    end
    local pointerBody = assert(text:match("function %%pointerLayout%b()%s*%-%>%s*i64%s*(%b{})"), text)
    assert(pointerBody:find("iconst.i64 8", 1, true) and not pointerBody:find("call", 1, true), pointerBody)
    assert(text:find("Nupp native graph: slotHash", 1, true), text)
    for _, invalid in ipairs({
        {"sizeOf<Alias>", "sizeOf<Missing>", "unknown type"},
        {"sizeOf<Alias>", "sizeOf<Alias, Alias>", "too many type arguments"},
        {"sizeOf<Alias>", "sizeOf", "native layout requires one explicit type argument"},
        {'fieldOffset<Alias>("word")', 'fieldOffset<Alias>("missing")', "native field offset: unknown field"}
    }) do
        local pattern = invalid[1]:gsub("([%(%)])", "%%%1")
        local changed, replacements = source:gsub(pattern, invalid[2], 1)
        assert(replacements == 1)
        assert(fs.writeFile(path, changed))
        local accepted, problem = pcall(lower.compile, ROOT, {path}, {include = {"src"}})
        os.remove(path)
        assert(not accepted and tostring(problem):find(invalid[3], 1, true), tostring(problem))
    end
end

function M.nativeUnsignedDivisionKeepsItsExactKindAndTrapOperation()
    local g = G.newNative({"uint64", "uint64"}, "uint64", "leaf")
    local b = G.block(g)
    G.emitNative(g, b, "NativeUDiv", {1, 2}, "uint64")
    b.term = {kind = "return", value = 1, edges = {}}
    G.verify(g)
    G.prune(g)
    G.verify(g)
    assert(clif.emit(g, {name = "unusedDivision"}):find("udiv", 1, true))
    local bad = G.newNative({"uint64", "uint64"}, "uint64", "leaf")
    local entry = G.block(bad)
    G.emitNative(bad, entry, "NativeUDiv", {1, 2}, "int64")
    entry.term = {kind = "return", value = 1, edges = {}}
    rejects(
        function()
            G.verify(bad)
        end,
        "native division requires two unsigned words"
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

function M.shapeLeavesUseTheSharedGraphAndLocalTailHashCalls()
    local text = lower.compile(
        ROOT,
        {
            ROOT .. "/src/nupp/runtime/vm/values.nupp",
            ROOT .. "/src/nupp/runtime/vm/objecthash.nupp",
            ROOT .. "/src/nupp/runtime/vm/objectshape.nupp"
        },
        {include = {"src"}}
    )
    for _, name in ipairs({"shapeCapacity", "shapeFill", "shapeFind"}) do
        local body = assert(text:match("function %%" .. name .. "%b()%s*%-%>%s*i64%s+tail%s*(%b{})"), text)
        assert(body:find("Nupp native graph: " .. name, 1, true), body)
        assert(not body:find("return_call_indirect", 1, true), body)
        if name ~= "shapeCapacity" then
            assert(body:find(" = %slotHash sig", 1, true), body)
            assert(body:find(" = (i64) -> i64 tail", 1, true), body)
            assert(body:find("load.i64 v", 1, true), body)
            assert(not body:find("notrap", 1, true), body)
        end
    end
end

function M.localLeafCallsRetainKindsAndRefuseManagedOrChangedCallees()
    local function callGraph()
        local g = G.newNative({"uint64"}, "uint64", "leaf")
        local b = G.block(g)
        G.emitNative(g, b, "NativeConstant", {"42"}, "uint64")
        local declaration = {
            moduleName = "nupp.runtime.vm.objecthash",
            name = "slotHash",
            params = {"uint64"},
            result = "uint64",
            abi = "leaf"
        }
        local answer = G.emitNative(g, b, "NativeLeafCall", {declaration, 1}, "uint64")
        b.term = {kind = "return", value = answer, edges = {}}

        return g, declaration
    end

    local g = callGraph()
    G.verify(g)
    G.prune(g)
    G.verify(g)
    local text = clif.emit(g, {name = "shapeCapacity"})
    assert(text:find("fn0 = %slotHash sig1", 1, true), text)
    assert(text:find("sig1 = (i64) -> i64 tail", 1, true), text)
    assert(not text:find("nupp_rt_", 1, true), text)
    for field, value in pairs({
        moduleName = "nupp.runtime.vm.helpers",
        name = "newTable",
        abi = "c",
        result = "int64"
    }) do
        local bad, declaration = callGraph()
        declaration[field] = value
        rejects(
            function()
                G.verify(bad)
            end,
            "native leaf declaration"
        )
    end
    local bad, declaration = callGraph()
    declaration.params[1] = "float64"
    rejects(
        function()
            G.verify(bad)
        end,
        "exact parameter kind"
    )
end

function M.borrowedLeafMemoryKeepsItsGuardsAndCannotClaimHandlerAccess()
    local g = G.newNative({"voidptr", "int64", "uint64"}, "uint64", "leaf")
    local b = G.block(g)
    local read = {source = "borrowed", kind = "uint64", width = 8, signed = false, write = false}
    local write = {source = "borrowed", kind = "uint64", width = 8, signed = false, write = true}
    local answer = G.emitNative(g, b, "NativeLoad", {1, 2, read}, "uint64")
    G.emitNative(g, b, "NativeStore", {1, 2, 3, write})
    b.term = {kind = "return", value = answer, edges = {}}
    G.verify(g)
    G.prune(g)
    G.verify(g)
    local text = clif.emit(g, {name = "shapeFind"})
    assert(text:find("load.i64 v", 1, true) and text:find("store v", 1, true), text)
    assert(not text:find("notrap", 1, true), text)
    read.source = "live"
    rejects(
        function()
            G.verify(g)
        end,
        "borrowed access semantics"
    )
end

function M.stringHashUsesBorrowedBytesAndKeepsItsStateInTheNuppGraph()
    local text = lower.compile(
        ROOT,
        {ROOT .. "/src/nupp/runtime/vm/values.nupp", ROOT .. "/src/nupp/runtime/vm/objecthash.nupp"},
        {include = {"src"}}
    )
    local body = assert(text:match("function %%stringHash%b()%s*%-%>%s*i64%s+tail%s*(%b{})"), text)
    assert(body:find("Nupp native graph: stringHash", 1, true), body)
    assert(body:find("uload8.i64 v", 1, true) and body:find("imul", 1, true), body)
    assert(not body:find("notrap", 1, true) and not body:find("call", 1, true), body)
end

function M.tableProbeUsesTheSharedLeafGraphAndNilBucketContract()
    local text = lower.compile(
        ROOT,
        {
            ROOT .. "/src/nupp/runtime/vm/values.nupp",
            ROOT .. "/src/nupp/runtime/vm/objecthash.nupp",
            ROOT .. "/src/nupp/runtime/vm/objecttable.nupp"
        },
        {include = {"src"}}
    )
    local body = assert(text:match("function %%tableProbe%b()%s*%-%>%s*i64%s+tail%s*(%b{})"), text)
    assert(body:find("Nupp native graph: tableProbe", 1, true), body)
    assert(body:find(" = %slotHash sig", 1, true) and body:find("load.i64 v", 1, true), body)
    assert(not body:find("notrap", 1, true) and not body:find("store", 1, true), body)
end

function M.tableGrowthLeavesRetainCheckedGraphCallsAndOwnedBufferAccess()
    local text = lower.compile(
        ROOT,
        {
            ROOT .. "/src/nupp/runtime/vm/values.nupp",
            ROOT .. "/src/nupp/runtime/vm/objecthash.nupp",
            ROOT .. "/src/nupp/runtime/vm/objecttable.nupp"
        },
        {include = {"src"}}
    )
    for _, name in ipairs({"tableCapacity", "tableNeedsGrowth", "tableInitialize", "tableLiveCount", "tableRehash"}) do
        local body = assert(text:match("function %%" .. name .. "%b()%s*%-%>%s*i64%s+tail%s*(%b{})"), text)
        assert(body:find("Nupp native graph: " .. name, 1, true), body)
        assert(not body:find("notrap", 1, true), body)
        if name == "tableRehash" then
            for _, callee in ipairs({"tableLiveCount", "tableCapacity", "tableProbe"}) do
                assert(body:find(" = %" .. callee .. " sig", 1, true), body)
            end
            assert(body:find("istore32", 1, true), body)
        end
    end
end

function M.rawLeafCallContractsKeepPointersAndEveryTransportedWord()
    local g = G.newNative({"voidptr", "uint64", "uint64", "uint64"}, "uint64", "leaf")
    local b = G.block(g)
    local declaration = G.nativeLeafDeclaration("nupp.runtime.vm.objecttable", "tableProbe")
    local answer = G.emitNative(g, b, "NativeLeafCall", {declaration, 1, 2, 3, 4}, "uint64")
    b.term = {kind = "return", value = answer, edges = {}}
    G.verify(g)
    G.prune(g)
    G.verify(g)
    local text = clif.emit(g, {name = "tableRehash"})
    assert(text:find("(i64, i64, i64, i64) -> i64 tail", 1, true), text)
    assert(text:find("call fn0(v1, v2, v3, v4)", 1, true), text)
    declaration.params[1] = "uint64"
    rejects(
        function()
            G.verify(g)
        end,
        "exact parameter kind"
    )
    local next = G.nativeLeafDeclaration("nupp.runtime.vm.objecttable", "tableProbe")
    assert(next.params[1] == "voidptr", "call-site metadata cannot mutate the approved contract")
end

function M.weakLookupPolicyIsAWordOnlySharedGraphLeaf()
    local text = lower.compile(ROOT, {ROOT .. "/src/nupp/runtime/vm/objectweak.nupp"}, {include = {"src"}})
    local body = assert(text:match("function %%weakLookupAction%b()%s*%-%>%s*i64%s+tail%s*(%b{})"), text)
    assert(body:find("Nupp native graph: weakLookupAction", 1, true), body)
    for _, operation in ipairs({"load", "store", "call", "notrap"}) do
        assert(not body:find(operation, 1, true), body)
    end
end

return M
