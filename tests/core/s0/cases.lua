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
        },
        {
            -- Saving lazily (the function dispatches by a tail call), a
            -- value live across a call is stored at the call, so the path
            -- that calls nothing stores nothing.
            name = "lazystore",
            text = identity
            .. [[
function %lazy(i64, i64) -> i64 tail {
    sig0 = (i64) -> i64 tail
    fn0 = %identity sig0
block0(v0: i64, v1: i64):
    brif v0, block1(), block2()
block1():
    v2 = call fn0(v1)
    v3 = iadd v2, v1
    return_call fn0(v3)
block2():
    return_call fn0(v1)
}
]],
            runs = {{args = {1, 5}, result = 10}, {args = {0, 7}, result = 7}},
            check = function(codes)
                for _, word in ipairs(codes.lazy.words) do
                    assert(not inspect.isFrameStore(word), "stores to the frame before its first branch")
                    if inspect.isConditionalBranch(word) then
                        break
                    end
                end
            end
        },
        {
            -- An `or` merged through a block parameter branches directly.
            name = "threading",
            text = [[
function %either(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = iconst.i64 10
    v3 = icmp ult v0, v2
    brif v3, block2(v3), block1()
block1():
    v4 = icmp ult v1, v2
    jump block2(v4)
block2(v5: i8):
    brif v5, block3(), block4()
block3():
    v6 = iconst.i64 1
    return v6
block4():
    v7 = iconst.i64 0
    return v7
}
]],
            runs = {{args = {3, 50}, result = 1}, {args = {50, 3}, result = 1}, {args = {50, 50}, result = 0}},
            check = function(codes)
                assert(
                    inspect.count(codes, "either", inspect.isConditionalSet) == 0,
                    "a comparison is set and tested again"
                )
                -- Both comparisons take the literal as an immediate.
                assert(inspect.count(codes, "either", inspect.isMoveWide) == 2, "makes the literal both take")
            end
        },
        {
            -- Two loads of neighbouring words from one base are one pair.
            name = "loadpair",
            text = [[
function %pairs(i64, i64) -> i64 tail {
    ss0 = explicit_slot 16, align = 16
block0(v0: i64, v1: i64):
    v2 = stack_addr.i64 ss0
    store v0, v2
    store v1, v2+8
    v3 = load.i64 v2
    v4 = load.i64 v2+8
    v5 = isub v3, v4
    return v5
}
]],
            runs = {{args = {50, 8}, result = 42}},
            check = function(codes)
                assert(inspect.count(codes, "pairs", inspect.isLoadPair) == 1, "the loads are not paired")
            end
        },
        {
            -- A shift feeding an add is the add's shifted operand; a multiply
            -- by a power of two is a shift.
            name = "shifts",
            text = [[
function %shifts(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = iconst.i64 4
    v3 = ishl v1, v2
    v4 = iadd v0, v3
    v5 = iconst.i64 8
    v6 = imul v4, v5
    return v6
}
]],
            runs = {{args = {1, 2}, result = 264}, {args = {-3, 1}, result = 104}},
            check = function(codes)
                assert(inspect.count(codes, "shifts", inspect.isMultiply) == 0, "a power of two is multiplied")
                assert(inspect.count(codes, "shifts", inspect.isShiftImmediate) == 1, "the shift is not fused")
            end
        },
        {
            -- Adding zero selects as nothing.
            name = "addzero",
            text = [[
function %addzero(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = iconst.i64 0
    v3 = iadd v0, v2
    v4 = iadd v3, v1
    return v4
}
]],
            runs = {{args = {40, 2}, result = 42}},
            check = function(codes)
                assert(inspect.count(codes, "addzero", inspect.isAddZero) == 0, "adds zero")
            end
        },
        {
            -- A value dead on one path does not hold its register there:
            -- the fast path computes the next argument into x0 itself,
            -- though x0's first value is used again on the slow path after.
            name = "holes",
            text = identity
            .. [[
function %holes(i64, i64) -> i64 tail {
    sig0 = (i64) -> i64 tail
    fn0 = %identity sig0
block0(v0: i64, v1: i64):
    brif v1, block1(), block2()
block1():
    v2 = iconst.i64 16
    v3 = iadd v0, v2
    return_call fn0(v3)
block2():
    v4 = call fn0(v0)
    v5 = iadd v4, v0
    return v5
}
]],
            runs = {{args = {5, 1}, result = 21}, {args = {5, 0}, result = 10}},
            check = function(codes)
                assert(inspect.count(codes, "holes", inspect.isMoveToFirst) == 0, "moves into x0 before the tail call")
            end
        },
        {
            -- A copy between two indexed words is a load and a store, each
            -- with the scaled index in its address: the load of the stored
            -- value, though nearer the store, is not the store's address.
            name = "indexedcopy",
            text = [[
function %copy(i64, i64, i64) -> i64 tail {
    ss0 = explicit_slot 32, align = 16
block0(v0: i64, v1: i64, v2: i64):
    v3 = stack_addr.i64 ss0
    store v2, v3+8
    v4 = iconst.i64 8
    v5 = imul v1, v4
    v6 = iadd v3, v5
    v7 = load.i64 v6
    v8 = imul v0, v4
    v9 = iadd v3, v8
    store v7, v9
    v10 = load.i64 v3
    return v10
}
]],
            runs = {{args = {0, 1, 42}, result = 42}},
            check = function(codes)
                assert(inspect.count(codes, "copy", inspect.isAddShifted) == 0, "an indexed address is added apart")
            end
        },
        {
            -- A table indexed by a byte (a dispatch on an opcode) is one
            -- load with the scaled index in its address.
            name = "indexeddispatch",
            text = [[
function %table(i64, i64) -> i64 tail {
    sig0 = (i64) -> i64 tail
block0(v0: i64, v1: i64):
    v5 = load.i64 v0
    v6 = uload8.i64 v1
    v7 = iconst.i64 3
    v8 = ishl v6, v7
    v9 = iadd v5, v8
    v10 = load.i64 v9
    return_call_indirect sig0, v10(v1)
}
]],
            runs = {},
            check = function(codes)
                assert(inspect.count(codes, "table", inspect.isShiftImmediate) == 0, "the index is shifted apart")
            end
        },
        {
            -- A shift reaches the add it feeds past a load whose address was
            -- fused into it: a fused add writes no register of its own. Nor
            -- does the literal shift amount, which the allocator may have
            -- placed where that load writes.
            name = "shiftpastfused",
            text = [[
function %pastfused(i64, i64) -> i64 tail {
    ss0 = explicit_slot 16, align = 16
block0(v0: i64, v1: i64):
    v2 = stack_addr.i64 ss0
    store v0, v2
    store v1, v2+8
    v3 = load.i64 v2
    v4 = iconst.i64 4
    v5 = ishl v3, v4
    v6 = iconst.i64 8
    v7 = iadd v2, v6
    v8 = load.i64 v7
    v9 = iadd v8, v5
    return v9
}
]],
            runs = {{args = {2, 3}, result = 35}},
            check = function(codes)
                assert(inspect.count(codes, "pastfused", inspect.isShiftImmediate) == 0, "the shift is not fused")
            end
        },
        {
            -- The same, from an argument's fields: base + 48 shifted, added
            -- to base + 40, as a code-end bound is.
            name = "shiftpastfieldload",
            text = [[
function %fields(i64, i64) -> i64 tail {
block0(v0: i64, v1: i64):
    v2 = iconst.i64 48
    v3 = iadd v0, v2
    v4 = load.i64 v3
    v5 = iconst.i64 4
    v6 = ishl v4, v5
    v7 = iconst.i64 40
    v8 = iadd v0, v7
    v9 = load.i64 v8
    v10 = iadd v9, v6
    v11 = icmp ult v1, v10
    brif v11, block1(v6), block2(v6)
block1(v12: i64):
    return v10
block2(v13: i64):
    return v1
}
]],
            runs = {},
            check = function(codes)
                assert(inspect.count(codes, "fields", inspect.isShiftImmediate) == 0, "the shift is not fused")
            end
        },
        {
            -- An indirect target loaded for its call alone is loaded into x16.
            name = "dispatch",
            text = [[
function %dispatch(i64, i64) -> i64 tail {
    sig0 = (i64) -> i64 tail
block0(v0: i64, v1: i64):
    v2 = load.i64 v0
    return_call_indirect sig0, v2(v1)
}
]],
            runs = {},
            check = function(codes)
                assert(inspect.count(codes, "dispatch", inspect.isMoveToScratch) == 0, "moves the target into x16")
            end
        }
    }
end
