local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local bytecode = require("nupp.compiler.vm.corebytecode")
local copies = require("nupp.compiler.vm.graphcopies")
local graph = require("nupp.compiler.vm.graph")
local M = {}

local function checked(text)
    local path, name = "=core_executable.nupp", "core_executable"
    local parsed = parser.parse(text, path)
    test.eq(#parsed.errors, 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new(".", {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local diagnostics = checker.check(parsed, path, env, {
        moduleName = name,
        strict = false,
        lints = {["unused-binding"] = "off"}
    })
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    local p = program.describe({{name = name, path = path, parsed = parsed, diagnostics = diagnostics}}, name)

    return program.compile(p, tagged)
end

local function refuses(action, message)
    local ok, problem = pcall(action)
    test.eq(ok, false)
    assert(tostring(problem):find(message, 1, true), tostring(problem))
end

local function identity(kind, value)
    return checked(
        "local function identity(value: "
        .. kind
        .. "): "
        .. kind
        .. " return value end\nreturn identity("
        .. value
        .. ")"
    )
end

function M.completeBooleanAndNilInitializersRetainActualClosureAndCall()
    for _, fixture in ipairs({{"boolean", "true"}, {"nil", "nil"}}) do
        local input = identity(fixture[1], fixture[2])
        local output = executable.fromChecked(input)
        executable.validate(output)
        test.eq(#output.functions, #input.catalog.owners)
        test.eq(output.frameDepth, 2)
        test.eq(output.instanceCapacity, 1)
        local root = output.functions[output.entry + 1]
        test.eq(#root.calls, 1)
        test.eq(root.closureCount, 1)
        local call = root.calls[1]
        test.eq(call.resultSlot, call.argumentBase + 1)
        test.eq(call.wanted, 1)
        test.eq(call.argumentCount, 1)
        test.eq(call.resumePC, call.pc + 1)
        test.eq(root.instructions[call.pc + 1][1], "CallK")
        test.eq(root.code:byte(call.pc * 16 + 4), 1)
        test.eq(root.code:byte(call.pc * 16 + 5), 1)
        test.eq(#root.code, root.instructionCount * 16)
        test.eq(executable.checkedOwner(output, call.target), input.catalog.owners[call.target + 1])
        for _, fn in ipairs(output.functions) do
            assert(fn.copyScratch < fn.callBase and fn.callBase + 1 < fn.valueCount)
            assert(fn.valueCount <= 250)
            for _, instruction in ipairs(fn.instructions) do
                assert(instruction[1] ~= "RetNil")
            end
        end
    end
end

function M.discardedResultsStillReserveOneSlotAndPreserveCalls()
    local output = executable.fromChecked(
        checked(
            [[
local function identity(value: boolean): boolean return value end
identity(false)
return identity(true)
]]
        )
    )
    local root = output.functions[output.entry + 1]
    test.eq(#root.calls, 2)
    test.eq(root.calls[1].discarded, true)
    test.eq(root.calls[2].discarded, false)
    for _, call in ipairs(root.calls) do
        test.eq(call.wanted, 1)
        test.eq(call.resultSlot, root.callBase + 1)
    end
end

function M.liveThroughValuesStayOutsideCallWindow()
    local output = executable.fromChecked(
        checked(
            [[
local function identity(value: boolean): boolean return value end
local held = true
local result = identity(false)
return held
]]
        )
    )
    local root = output.functions[output.entry + 1]
    local call = root.calls[1]
    local continuation = root.instructions[call.resumePC + 1]
    assert(continuation[1] == "Move" or continuation[1] == "Jmp")
    local moves = 0
    for pc = call.resumePC + 1, #root.instructions do
        local ins = root.instructions[pc]
        if ins[1] == "Jmp" then
            break
        end
        test.eq(ins[1], "Move")
        assert(ins[2] < root.copyScratch)
        moves = moves + 1
    end
    assert(moves > 0)
end

function M.parallelCopiesPreserveCyclesDuplicatesAndIdentity()
    local moves = copies.schedule({1, 2, 3, 4}, {2, 1, 1, 4}, 5)
    local words = {"first", "second", "third", "fourth"}
    for _, move in ipairs(moves) do
        words[move[1]] = words[move[2]]
    end
    test.eq(words[1], "second")
    test.eq(words[2], "first")
    test.eq(words[3], "first")
    test.eq(words[4], "fourth")
    test.eq(#moves, 4)
    refuses(
        function()
            copies.schedule({1}, {5}, 5)
        end,
        "scratch overlaps"
    )
end

function M.absentReturnsRefuseIncludingUnusedCatalogOwners()
    refuses(
        function()
            executable.fromChecked(checked("local function unused(): nil return end\nreturn true"))
        end,
        "absent return"
    )
    refuses(
        function()
            executable.fromChecked(checked("return"))
        end,
        "absent return"
    )
end

function M.flaggedArgumentCountsAndPhysicalOverflowRefuse()
    local params, args = {}, {}
    for index = 1, 64 do
        params[index], args[index] = "p" .. index .. ": boolean", "true"
    end
    refuses(
        function()
            executable.fromChecked(
                checked(
                    "local function many(" .. table.concat(
                        params,
                        ","
                    ) .. "): boolean return p1 end\nreturn many(" .. table.concat(args, ",") .. ")"
                )
            )
        end,
        "capacity"
    )
    -- Slots are reused after a value's last use, so overflow needs that many
    -- values live at once: every local is transported through the join.
    -- Lua allows 200 active locals, so the widest live set is 63 parameters
    -- plus 190 locals transported through one join.
    local wide, locals, actual = {}, {}, {}
    for index = 1, 63 do
        wide[index], actual[index] = "p" .. index .. ": boolean", "true"
    end
    for index = 1, 190 do
        locals[index] = "local v" .. index .. " = true"
    end
    refuses(
        function()
            executable.fromChecked(
                checked(
                    "local function wide(" .. table.concat(
                        wide,
                        ", "
                    ) .. "): boolean\n" .. table.concat(
                        locals,
                        "\n"
                    ) .. "\nif p1 then v1 = false end\nreturn v190\nend\nreturn wide(" .. table.concat(
                        actual,
                        ", "
                    ) .. ")"
                )
            )
        end,
        "physical slots"
    )
    refuses(
        function()
            bytecode.encode({"CallK", 1, 10, 10, 64, 1})
        end,
        "fixed CallK"
    )
    -- Wanting none is wanting every result as one pack.
    assert(bytecode.encode({"CallK", 1, 10, 10, 0, 0}), "an open CallK encodes")
    refuses(
        function()
            bytecode.encode({"CallK", 1, 10, 10, 0, 17})
        end,
        "fixed CallK"
    )
end

function M.byteRecipesBindCanonicalOperandsAndFieldOffsets()
    local call = bytecode.encode({"CallK", 7, 10, 10, 3, 1})
    local desc = bytecode.describe("CallK")
    test.eq(call:byte(1), desc.id)
    test.eq(call:byte(2), 10)
    test.eq(call:byte(3), 10)
    test.eq(call:byte(4), 3)
    test.eq(call:byte(5), 1)
    test.eq(call:byte(9), 7)
    local closure = bytecode.encode({"NewClosure", 4, 7, 9, 0})
    test.eq(closure:byte(2), 4)
    test.eq(closure:byte(3), 9)
    test.eq(closure:byte(4), 0)
    test.eq(closure:byte(9), 7)
    local back = bytecode.encode({"Jmp", -1})
    for at = 5, 8 do
        test.eq(back:byte(at), 255)
    end
    refuses(
        function()
            bytecode.encode({"RetNil"})
        end,
        "unsupported final-core encoding"
    )
end

function M.protectedCallsEncodeTheirOptionalSpreadRegister()
    local fixed = bytecode.encode({"PCall", 7, 10, 10, 3, 2})
    local spread = bytecode.encode({"PCall", 7, 10, 10, 3, 2, 9})
    test.eq(fixed:byte(6), 0)
    test.eq(spread:byte(6), 9)
    refuses(
        function()
            bytecode.encode({"PCall", 7, 10, 10, 3, 2, 251})
        end,
        "pack register"
    )
    refuses(
        function()
            bytecode.encode({"PCall", 7, 190, 190, 3, 2, 9})
        end,
        "spread window"
    )
end

function M.copiedOrMutatedExecutableDoesNotRetainCheckedBinding()
    local output = executable.fromChecked(identity("boolean", "true"))
    local fake = {}
    for key, value in pairs(output) do
        fake[key] = value
    end
    refuses(
        function()
            executable.checkedOwner(fake, 0)
        end,
        "unissued executable"
    )
    output.functions[1].code = "changed"
    refuses(
        function()
            executable.validate(output)
        end,
        "metadata changed"
    )
end

function M.frozenGraphRouteStillRefusesInvoke()
    local input = identity("boolean", "true")
    refuses(
        function()
            graph.lower(input.graphs[1])
        end,
        "invoke requires final-core"
    )
end

return M
