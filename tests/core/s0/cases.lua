-- The cases run.lua selects and runs: IR text (nupp.compiler.s0.reader),
-- runs of integer arguments with the result each must give, and what the
-- selected code must or must not contain. `inspect` is run.lua's.
return function(inspect)
    local arm = inspect.arm

    -- A callee for the cases that need values to live across a call.
    local identity = [[
function %identity(i64) -> i64 tail {
block0(v0: i64):
    return v0
}
]]

    return {
        {
            name = "leaf",
            text = [[
function %leaf(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = iadd v0, v1
    return v2
}
]],
            runs = {{args = {2, 40}, result = 42}, {args = {-1, 1}, result = 0}},
            check = function(codes)
                -- A function that calls nothing leaves LR where it is.
                assert(codes.leaf.words[1] ~= arm.str(8, 30, 23, 0), "leaf saves LR")
            end
        },
        {
            -- A block that stores its parameter on entry (it lives across
            -- a call) and only jumps on is still entered: branches to it
            -- were once sent past it, and the call's result added garbage.
            name = "parameterstore",
            text = identity
            .. [[
function %merge(i64, i64) -> i64 tail {
    sig0 = (i64) -> i64 tail
    fn0 = %identity sig0
block0(v0: i64, v1: i64):
    v2 = iconst.i64 1
    v3 = iconst.i64 2
    brif v0, block1(v2), block2(v3)
block1(v10: i64):
    jump block3(v10)
block2(v11: i64):
    jump block3(v11)
block3(v4: i64):
    jump block4(v4)
block4(v5: i64):
    v6 = call fn0(v1)
    v7 = iadd v5, v6
    return v7
}
]],
            runs = {{args = {1, 100}, result = 101}, {args = {0, 100}, result = 102}}
        }
    }
end
