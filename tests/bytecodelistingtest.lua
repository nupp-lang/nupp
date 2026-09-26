local listing = require("nupp.tools.bytecodelisting")

local M = {}

local function instruction(pc, op, text, line)
    return {pc = pc, op = op, text = text, line = line}
end

function M.preambleSlotsDoNotHideNestedAuthoredFunctions()
    local boundary = {
        depth = 0,
        instructions = {
            instruction(1, "FNEW", "0001  FNEW     0   7", 1),
            instruction(2, "KSTR", "0002  KSTR     0   8", 1),
        },
    }
    local generated = {depth = 1, slot = 7, instructions = {instruction(0, "FUNCF", "0000  FUNCF    1", 1)},}
    local generatedChild = {depth = 2, slot = 1, instructions = {instruction(0, "FUNCF", "0000  FUNCF    1", 1)},}
    local authored = {depth = 1, slot = 8, instructions = {instruction(0, "FUNCF", "0000  FUNCF    1", 2)},}
    local authoredChild = {depth = 2, slot = 7, instructions = {instruction(0, "FUNCF", "0000  FUNCF    1", 3)},}

    local byLine, preamble, built = listing.group(
        {boundary, generated, generatedChild, authored, authoredChild},
        boundary,
        2
    )
    assert(#preamble == 3, "the boundary instruction, generated child, and descendant are folded")
    assert(built == 2, "both generated functions are counted")
    assert(#byLine[2] == 1, "the authored function remains visible")
    assert(#byLine[3] == 1, "a repeated slot under the authored function remains visible")
end

return M
