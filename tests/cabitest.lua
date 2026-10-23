local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local cabi = require("nupp.compiler.cinterop.cabi")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function checked(source)
    local result = parser.parse(source, "src/game.nupp")
    testAssert.equal(#result.errors, 0, "parse errors")
    local env = envMod.new(HERE .. "/..", {cache = false})
    local diagnostics, _, exports = check.check(result, "src/game.nupp", env, {moduleName = "game"})
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity == "error" then
            error(diagnostic.code .. ": " .. diagnostic.msg, 2)
        end
    end

    return assert(exports), result
end

local SOURCE = [[
local game = {}

struct game.Position
    x: float
    y: float
end

struct game.Motion
    position: game.Position
    flags: uint32
end

return game
]]

local TARGET = "x86_64-unknown-linux-gnu"
local M = {}

function M.canonicalIdentityIsNominalAndModuleQualified()
    local exports = checked(SOURCE)
    local position = assert(exports.types.Position)
    local motion = assert(exports.types.Motion)
    testAssert.equal(cabi.identity(position), "game.Position")
    testAssert.equal(cabi.identity(motion), "game.Motion")
    local a = assert(cabi.aggregate(position, TARGET))
    local b = assert(cabi.aggregate(motion, TARGET))
    assert(a.typedef ~= b.typedef, "distinct declarations keep distinct C names")
    testAssert.equal(a.typedef, "nupp_4_game_8_Position")
end

function M.descriptionCarriesTargetLayoutAndSemanticFingerprints()
    local exports = checked(SOURCE)
    local description = assert(cabi.aggregate(exports.types.Motion, TARGET))
    testAssert.equal(description.schema, cabi.ABI)
    testAssert.equal(description.target, TARGET)
    testAssert.equal(description.size, 12)
    testAssert.equal(description.alignment, 4)
    testAssert.equal(description.fields[1].offset, 0)
    testAssert.equal(description.fields[2].offset, 8)
    assert(#description.semanticFingerprint == 64, "semantic SHA-256")
    assert(#description.layoutFingerprint == 64, "layout SHA-256")
end

function M.headerOrdersByValueDependenciesAndAssertsEveryOffset()
    local exports = checked(SOURCE)
    local position = assert(cabi.aggregate(exports.types.Position, TARGET))
    local motion = assert(cabi.aggregate(exports.types.Motion, TARGET))
    local header = assert(cabi.header({position, motion}, {}, "GAME_NUPP_H"))
    local positionAt = assert(header:find("struct " .. position.tag, 1, true))
    local motionAt = assert(header:find("struct " .. motion.tag, 1, true))
    assert(positionAt < motionAt, "an embedded dependency is defined first")
    assert(header:find("offsetof(" .. motion.typedef .. ", position) == 0", 1, true))
    assert(header:find("offsetof(" .. motion.typedef .. ", flags) == 8", 1, true))
    local repeated = assert(cabi.header({position, motion}, {}, "GAME_NUPP_H"))
    testAssert.equal(repeated, header, "header output is deterministic")
end

function M.oneFunctionRecordRendersTypedAndErasedPointers()
    local exports = checked(SOURCE)
    local position = exports.types.Position
    local pointer = require("nupp.compiler.types").ptr(position)
    local signature = cabi.functionRecord(
        "integrate",
        {
            {name = "position", type = pointer, mode = "exclusive"},
            {name = "dt", type = require("nupp.compiler.types").float, mode = "plain"},
        },
        nil
    )
    testAssert.equal(
        assert(cabi.prototype(signature, false)),
        "void integrate(nupp_4_game_8_Position *position, float dt);"
    )
    testAssert.equal(assert(cabi.prototype(signature, true)), "void integrate(void *, float);")
end

function M.aPointerToAnArrayKeepsItsParentheses()
    -- A pointer to four ints, not four pointers.
    local T = require("nupp.compiler.types")
    local row = T.ptr(T.carray(T.int32, 4))
    local rows = T.carray(T.ptr(T.int32), 4)
    testAssert.equal(cabi.declaration(row, "row", "ffi"), "int32_t (*row)[4]")
    testAssert.equal(cabi.declaration(rows, "rows", "ffi"), "int32_t *rows[4]")
end

function M.aGuardIsAlwaysACIdentifier()
    local exports = checked(SOURCE)
    local position = assert(cabi.aggregate(exports.types.Position, TARGET))
    local header = assert(cabi.header({position}, {}, "3d-game.h"))
    assert(header:find("#ifndef NUPP_3D_GAME_H\n", 1, true), header:sub(1, 120))
    local absolute = assert(cabi.header({position}, {}, "/tmp/out/game.h"))
    assert(
        absolute:find("#ifndef TMP_OUT_GAME_H\n", 1, true),
        "no reserved leading underscore: " .. absolute:sub(1, 120)
    )
end

function M.functionRecordsRejectUnmodelledCallingConventions()
    local signature = cabi.functionRecord("callback", {}, nil, false, "stdcall")
    local prototype, why = cabi.prototype(signature)
    testAssert.equal(prototype, nil)
    testAssert.equal(why, "the C function signature has an unsupported calling convention")
end

function M.layoutAndSemanticChangesAlterThePublishedFingerprints()
    local first = checked(SOURCE)
    local changed = checked(SOURCE:gsub("flags: uint32", "flags: uint16"))
    local a = assert(cabi.aggregate(first.types.Motion, TARGET))
    local b = assert(cabi.aggregate(changed.types.Motion, TARGET))
    assert(a.semanticFingerprint ~= b.semanticFingerprint, "field width is semantic")
    assert(a.layoutFingerprint ~= b.layoutFingerprint, "field width changes the ABI")

    local wide = checked(SOURCE:gsub("flags: uint32", "flags: number"))
    local lp64 = assert(cabi.aggregate(wide.types.Motion, TARGET))
    local ilp32 = assert(cabi.aggregate(wide.types.Motion, "i686-unknown-linux-gnu"))
    assert(lp64.layoutFingerprint ~= ilp32.layoutFingerprint, "target is fingerprinted")
    assert(
        lp64.alignment ~= ilp32.alignment or lp64.size ~= ilp32.size,
        "the 32- and 64-bit models produce observably distinct layouts"
    )
end

function M.pointerRecursionUsesForwardDeclarations()
    local exports = checked([[
local game = {}
struct game.Node
    value: int32
    next: game.Node*
end
return game
]])
    local node = assert(cabi.aggregate(exports.types.Node, TARGET))
    testAssert.equal(#node.dependencies, 0, "a pointer is not a by-value dependency")
    testAssert.equal(node.pointerDependencies[1], exports.types.Node, "the recursive pointer is recorded")
    local header = assert(cabi.header({node}, {}, "NODE_H"))
    local forward = assert(header:find("typedef struct " .. node.tag, 1, true))
    local body = assert(header:find("struct " .. node.tag .. " {", 1, true))
    assert(forward < body, "the recursive tag is declared before its pointer field")
end

function M.byValueCyclesAreRejectedBeforeEmission()
    local source = [[
local game = {}
struct game.Left
    right: game.Right
end
struct game.Right
    left: game.Left
end
return game
]]
    local parsed = parser.parse(source, "src/game.nupp")
    local diagnostics = check.check(
        parsed,
        "src/game.nupp",
        envMod.new(HERE .. "/..", {
            cache = false
        }),
        {
            moduleName = "game"
        }
    )
    testAssert.equal(diagnostics[1] and diagnostics[1].code, "NUPP2201")
    assert(
        diagnostics[1].msg:find("contain itself", 1, true),
        "the source diagnostic explains why the layout is impossible"
    )
end

function M.vmForeignSignaturesUseCheckedTypes()
    local metadata = require("nupp.compiler.vm.metadata")
    local T = require("nupp.compiler.types")
    local declaration = {cAbiSignature = cabi.functionRecord("strlen", {{type = T.cstring, mode = "plain"}}, T.uint64)}
    local signature = metadata.foreignSignature(declaration)
    testAssert.equal(signature.params[1].kind, "pointer")
    testAssert.equal(signature.params[1].readonly, true)
    testAssert.equal(signature.result, "uint64")
    local pointer = {tag = "ptr", elem = {tag = "const", inner = T.uint8}}
    declaration.cAbiSignature.params[1].type = pointer
    local readonly = metadata.foreignSignature(declaration)
    testAssert.equal(readonly.params[1].readonly, true)
    pointer.elem = T.uint8
    testAssert.equal(metadata.foreignSignature(declaration).params[1], "pointer")
    -- A variadic function's extra arguments are typed per call.
    local variadic = {cAbiSignature = cabi.functionRecord("printf", {{type = T.cstring, mode = "plain"}}, T.int32)}
    variadic.cAbiSignature.varargs = true
    testAssert.equal(metadata.foreignSignature(variadic).variadic, true)
    local cases = {
        {
            change = function(d)
                d.cAbiSignature.params[1].mode = "out"
            end,
            -- Out parameters are supported; one that is no pointer has no slot.
            reason = "out parameter is a pointer to its slot"
        },
        {
            change = function(d)
                d.cAbiSignature.params[1].type = T.any
            end,
            reason = "parameter 1 type any"
        },
        {
            change = function(d)
                d.cAbiSignature.result = T.any
            end,
            reason = "result type any"
        },
    }
    for _, case in ipairs(cases) do
        local candidate = {cAbiSignature = cabi.functionRecord("test", {{type = T.cstring, mode = "plain"}}, T.uint64)}
        case.change(candidate)
        local ok, why = pcall(metadata.foreignSignature, candidate)
        assert(not ok and tostring(why):find(case.reason, 1, true), case.reason .. ": " .. tostring(why))
    end
end

return M
