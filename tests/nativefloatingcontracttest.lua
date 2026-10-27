local program = require("nupp.compiler.vm.programcontract")
local slots = require("nupp.compiler.vm.slotcontract")
local M = {}

local function declaration(name, fields)
    local arguments = {}
    for key, value in pairs(fields) do
        arguments[#arguments + 1] = {name = key, kind = "value", value = value}
    end

    return {annotations = {{name = name, arguments = arguments}}}
end

local function refuses(call)
    local ok, problem = pcall(call)
    assert(not ok, "accepted an ambiguous native floating contract")
    assert(tostring(problem):find("invalid kind", 1, true), tostring(problem))
end

function M.programFloatLoadsRetainExactFloat64MeaningAndBodyLifetime()
    local definition = declaration("vmProgramLoad", {source = "code", kind = "float64", lifetime = "body"})
    local contract = program.read(definition, "readFloat")
    assert(contract.kind == "float64" and contract.result == "float64" and contract.width == 8)
    assert(contract.source == "code" and contract.lifetime == "body")
    for _, kind in ipairs({"number", "float32"}) do
        refuses(function()
            program.read(declaration("vmProgramLoad", {source = "code", kind = kind, lifetime = "body"}), "readFloat")
        end)
    end
end

function M.floatWindowsRequireFloat64WithoutChangingIntegerOrVectorWindows()
    for _, write in ipairs({false, true}) do
        local contract = slots.read(
            declaration("vmSlotAccess", {
                class = "f",
                kind = "float64",
                write = write
            }),
            "floatSlot"
        )
        assert(contract.kind == "float64" and contract.width == 8 and contract.write == write)
        for _, kind in ipairs({"number", "float32"}) do
            refuses(function()
                slots.read(declaration("vmSlotAccess", {class = "f", kind = kind, write = write}), "floatSlot")
            end)
        end
    end
    local integer = slots.read(declaration("vmSlotAccess", {class = "i", kind = "int64", write = false}), "integerSlot")
    assert(integer.kind == "int64" and integer.width == 8)
    local vector = slots.read(
        declaration("vmSlotAccess", {
            class = "xHigh",
            kind = "uint64",
            write = false
        }),
        "vectorSlot"
    )
    assert(vector.kind == "uint64" and vector.width == 16 and vector.offset == 8)
end

return M
