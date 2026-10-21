-- The opcode table: the one definition of the VM's opcodes, which the lowering
-- checks every emission against and the image carries in its header. The
-- runtime reads an image that carries none against a built-in copy, kept in
-- `native/crates/vm/src/opcodes.table`; this suite holds that copy equal to
-- what the compiler emits. NUPP_WRITE_OPCODE_TABLE=1 rewrites it.
local test = require("nupp.test")
local opcodes = require("nupp.compiler.vm.opcodes")
local lowerstate = require("nupp.compiler.vm.lowerstate")
local fs = require("nupp.compiler.fs")

local HERE = fs.absolute(assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")))
local TABLE = fs.absolute(HERE .. "/../native/crates/vm/src/opcodes.table")

local M = {}

function M.theBuiltInCopyIsWhatTheCompilerEmits()
    local expected = table.concat(opcodes.header(), "\n") .. "\n"
    if os.getenv("NUPP_WRITE_OPCODE_TABLE") == "1" then
        local file = assert(io.open(TABLE, "wb"))
        file:write(expected)
        file:close()
    end
    local file = assert(io.open(TABLE, "rb"), "the built-in opcode table is missing: " .. TABLE)
    local actual = file:read("*a")
    file:close()
    test.equal(actual, expected, "native/crates/vm/src/opcodes.table is stale; NUPP_WRITE_OPCODE_TABLE=1 rewrites it")
end

function M.everyRowSpellsItsOperands()
    test.equal(#opcodes.order, 168)
    local names = {}
    for _, name in ipairs(opcodes.order) do
        test.assert(not names[name], name .. " listed twice")
        names[name] = true
        local opcode = opcodes.byName[name]
        test.equal(opcode.name, name)
        test.assert(opcode.min <= opcode.max)
        test.equal(opcode.max, #opcode.operands)
    end
    test.equal(opcodes.byName.Simd.min, 4)
    test.equal(opcodes.byName.Simd.max, 5)
    test.equal(opcodes.byName.CallK.flow, "next")
    test.equal(opcodes.byName.Jmp.flow, "jump")
    test.equal(opcodes.byName.Switch.flow, "table")
    test.equal(opcodes.byName.Ret.flow, "stop")
    test.equal(opcodes.functionOperand.NewClosure, 2)
    test.equal(opcodes.functionOperand.Call, 1)
    test.equal(opcodes.shapeOperand.GetSlot, 4)
    test.equal(opcodes.shapeOperand.SetMethod, 1)
    test.equal(opcodes.shapeOperand.K, nil)
end

local function fails(instruction)
    local ok, err = pcall(opcodes.check, instruction)
    test.assert(not ok, "accepted an instruction the table does not describe")

    return tostring(err)
end

function M.theLoweringRefusesWhatTheTableDoesNotDescribe()
    opcodes.check({"K", 1, 0})
    opcodes.check({"RetNil"})
    opcodes.check({"Simd", "add", "f64", 3, 2})
    opcodes.check({"Simd", "add", "f64", 3, 2, "f32"})
    opcodes.check({"Jmp", 0})
    opcodes.check({"IK", 1, "9007199254740993"})
    opcodes.check({"IK", 1, "-1"})
    test.matches(fails({"Kk", 1, 0}), "unknown opcode Kk")
    test.matches(fails({"K", 1}), "K takes 2 operands, not 1")
    test.matches(fails({"K", 1, 0, 0}), "K takes 2 operands, not 3")
    test.matches(fails({"Simd", "add", "f64", 3}), "Simd takes 4 to 5 operands, not 3")
    test.matches(fails({"Simd", 1, "f64", 3, 2}), "operand 1 must be a name")
    test.matches(fails({"K", "r1", 0}), "operand 1 must be a number")
    test.matches(fails({"K", 1, "0"}), "operand 2 must be a number")
    test.matches(fails({"IK", 1, "one"}), "operand 2 must be an immediate")
    test.matches(fails({}), "unknown opcode nil")
end

function M.anEmittedInstructionGoesThroughTheTable()
    local f = setmetatable({id = 0, name = "t", blocks = {}}, lowerstate.Fn)
    f:op("Nil", 1)
    local done = f:label()
    f:jump(done)
    f:place(done)
    test.equal(#f.blocks[1].code, 1)
    test.equal(f.blocks[1].ends, "jump")
    test.assert(f.blocks[1].target == done, "the jump names its label")
    test.assert(not pcall(f.op, f, "Nill", 1))
    test.assert(not pcall(f.op, f, "Nil", 1, 2))
    -- A jump is a block's ending, which only jump and branch write.
    test.assert(not pcall(f.op, f, "Jmp", 0))
    test.equal(#f.blocks[1].code, 1)
end

return M
