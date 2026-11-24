-- Code cases for the owned backend (nupp.compiler.s0): small IR functions,
-- each selected by the backend as this checkout has it, checked for the
-- instructions it is meant to select, and run natively through the core
-- bridge on inputs whose results are known. Seconds per case, no runtime
-- build: what a change to the backend breaks shows here first.
--
--   cd tests/core/s0 && NUPP_COMPILER_ROOT=$PWD/../../.. ../../../bin/nupp run run.lua [CASE...]
--
-- `nupp run` resolves nupp.compiler.s0 to the compiler running it, so the
-- backend's sources are staged under build/s0cases as `s0lab` first.
-- NUPP_S0_DISASSEMBLE=1 prints each case's code (clang and llvm-objdump).
local ROOT = assert(os.getenv("NUPP_COMPILER_ROOT"), "set NUPP_COMPILER_ROOT")
local STAGE = ROOT .. "/build/s0cases"
local OUT = STAGE .. "/out"

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local bytes = file:read("*a")
    file:close()

    return bytes
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
end

local function shell(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()

    return tonumber(output:match("__exit__:(%d+)%s*$")), (output:gsub("__exit__:%d+%s*$", ""))
end

-- Stage the backend under s0lab.*, with the internal module it reads.
assert(os.execute("mkdir -p " .. quote(STAGE .. "/s0lab") .. " " .. quote(OUT)))
local _, listing = shell("ls " .. quote(ROOT .. "/src/nupp/compiler/s0"))
local sources = {}
for name in listing:gmatch("[%w_]+%.nupp") do
    sources[#sources + 1] = {ROOT .. "/src/nupp/compiler/s0/" .. name, STAGE .. "/s0lab/" .. name}
end
sources[#sources + 1] = {ROOT .. "/src/nupp/compiler/floatparts.nupp", STAGE .. "/s0lab/floatparts.nupp"}
for _, pair in ipairs(sources) do
    local text = assert(read(pair[1]), pair[1])
    text = text:gsub("nupp%.compiler%.s0%.", "s0lab."):gsub("nupp%.compiler%.floatparts", "s0lab.floatparts")
    if read(pair[2]) ~= text then
        write(pair[2], text)
    end
end

local reader = require("s0lab.reader")
local allocate = require("s0lab.allocate")
local check = require("s0lab.allocationcheck")
local selector = require("s0lab.select")
local inliner = require("s0lab.inline")
local arm = require("s0lab.arm64")
local ir = require("s0lab.ir")
local transport = require("nupp.core.transportbundle")
local cases = dofile(ROOT .. "/tests/core/s0/cases.lua")

-- The bridge's scratch: the arena the code spills into starts past SPILL.
local SCRATCH = 1048576
local SPILL = 65536
local BRIDGE = ROOT .. "/build/c-core-bridge/nupp-core"

local function bridge()
    if read(BRIDGE) then
        return BRIDGE
    end
    local status, output = shell("sh " .. quote(ROOT .. "/scripts/core-bridge"))
    assert(status == 0, "bridge build failed: " .. output)

    return assert(output:match("([^\r\n]+)\r?\n?$")) .. "/nupp-core"
end

local function le(words, size)
    local out = {}
    for index, value in ipairs(words) do
        local bytes = {}
        for at = 0, size - 1 do
            bytes[at + 1] = string.char((value >> (at * 8)) & 255)
        end
        out[index] = table.concat(bytes)
    end

    return table.concat(out)
end

local function word64(bytes, index)
    local value = 0
    for at = 8, 1, -1 do
        value = (value << 8) | bytes:byte((index - 1) * 8 + at)
    end

    return value
end

-- Selects every function of `text`; answers them by name, and the entry's.
local function select(text, spill, inlined)
    local codes, order = {}, {}
    local functions = reader.read(text)
    -- Calls between the case's own functions are inlined first, from
    -- pristine copies (read again) of the callees.
    if inlined then
        local pristine = {}
        for _, f in ipairs(reader.read(text)) do
            pristine[f.name] = f
        end
        for _, f in ipairs(functions) do
            inliner.all(f, function(name)
                return pristine[name]
            end)
        end
    end
    for _, f in ipairs(functions) do
        local target = selector.target()
        if spill then
            target.integerRegisters, target.floatRegisters = {}, {}
        end
        local a = allocate.run(f, target)
        if os.getenv("NUPP_S0_ALLOCATION") == "1" then
            for v = 1, #f.valueKinds do
                if f.valueKinds[v] ~= 0 then
                    print(
                        (
                            "%s v%d at %d save %d interval %d-%d ranges %s"
                        ):format(
                            f.name,
                            v,
                            a.location[v],
                            a.saveSlot[v],
                            a.start[v],
                            a.finish[v],
                            table.concat(a.ranges[v] or {}, ",")
                        )
                    )
                end
            end
        end
        check.run(f, target, a)
        codes[f.name] = selector.run(f, a)
        order[#order + 1] = f.name
    end

    return codes, order
end

-- A bundle the bridge runs: a C-boundary shim that passes input words 1..n
-- as the entry's integer arguments and answers its x0, then the functions.
local function bundle(codes, order, entry, arity)
    local words = {}

    local function emit(word)
        words[#words + 1] = word
        return #words
    end

    emit(arm.sub_imm(64, 31, 31, 176, 0))
    for reg = 19, 29, 2 do
        emit(arm.stp(64, reg, reg + 1, 31, (reg - 19) * 8, 0))
    end
    for reg = 8, 14, 2 do
        emit(arm.stp_fp(64, reg, reg + 1, 31, 96 + (reg - 8) * 8, 0))
    end
    emit(arm.str(8, 1, 31, 160))
    emit(arm.str(8, 30, 31, 168))
    emit(arm.ldr(8, 19, 0, 40))
    emit(arm.ldr(8, 22, 0, 56))
    emit(arm.ldr(8, 20, 0, 72))
    emit(arm.add_imm(64, 23, 19, SPILL >> 12, 1))
    for at = 1, arity do
        emit(arm.ldr(8, at - 1, 20, at * 8))
    end
    local call = emit(arm.bl(0))
    emit(arm.ldr(8, 16, 31, 160))
    emit(arm.str(8, 0, 16, 0))
    emit(arm.str(8, 31, 16, 8))
    emit(arm.movz(64, 0, 0, 0))
    for reg = 8, 14, 2 do
        emit(arm.ldp_fp(64, reg, reg + 1, 31, 96 + (reg - 8) * 8, 0))
    end
    for reg = 19, 29, 2 do
        emit(arm.ldp(64, reg, reg + 1, 31, (reg - 19) * 8, 0))
    end
    emit(arm.ldr(8, 30, 31, 168))
    emit(arm.add_imm(64, 31, 31, 176, 0))
    emit(arm.ret(30))
    local offsets = {}
    for _, name in ipairs(order) do
        offsets[name] = #words
        for _, word in ipairs(codes[name].words) do
            emit(word)
        end
    end
    words[call] = arm.bl((offsets[entry] + 1 - call) * 4)
    for _, name in ipairs(order) do
        local code = codes[name]
        for fixup, at in ipairs(code.fixupWord) do
            local kind, callee = code.fixupKind[fixup], code.fixupName[fixup]
            assert(kind == selector.B26 or kind == selector.BL26, "case code imports " .. callee)
            local slot = offsets[name] + at
            local delta = (offsets[assert(offsets[callee] and callee, "unknown callee " .. callee)] + 1 - slot) * 4
            words[slot] = kind == selector.B26 and arm.b(delta) or arm.bl(delta)
        end
    end

    return transport.encode("aarch64", 0, le(words, 4), string.rep("\0", 8), SCRATCH, 2), words
end

local function disassemble(name, words)
    local raw = OUT .. "/" .. name .. ".bin"
    write(raw, le(words, 4))
    write(OUT .. "/" .. name .. ".s", '.text\n.globl _code\n_code:\n.incbin "' .. raw .. '"\n')
    local status, text = shell(
        "clang -c -arch arm64 -o " .. quote(
            OUT .. "/" .. name .. ".o"
        ) .. " " .. quote(
            OUT .. "/" .. name .. ".s"
        ) .. " && objdump -d --no-show-raw-insn " .. quote(OUT .. "/" .. name .. ".o")
    )
    print(status == 0 and text or "disassembly failed: " .. text)
end

-- What a case may assert about the code it selects (cases.lua).
local inspect = {}

-- The words of function `name`, each as the encoder spells it.
function inspect.words(codes, name)
    return codes[name].words
end

-- How many of `name`'s words `predicate` accepts.
function inspect.count(codes, name, predicate)
    local count = 0
    for _, word in ipairs(codes[name].words) do
        if predicate(word) then
            count = count + 1
        end
    end

    return count
end

inspect.arm = arm

-- A 64-bit store to the arena frame (x23).
function inspect.isFrameStore(word)
    return word & 0xffc00000 == 0xf9000000 and (word >> 5) & 31 == 23
end

function inspect.isConditionalBranch(word)
    return word & 0xff000010 == 0x54000000
end

-- cset: csinc wd, wzr, wzr, cond.
function inspect.isConditionalSet(word)
    return word & 0xffff0fe0 == 0x1a9f07e0
end

-- ldp of two 64-bit registers at a signed offset.
function inspect.isLoadPair(word)
    return word & 0xffc00000 == 0xa9400000
end

-- madd (mul is madd with xzr).
function inspect.isMultiply(word)
    return word & 0x7fe08000 == 0x1b000000
end

-- ubfm/sbfm (lsl, lsr, asr by an immediate) on 64 bits.
function inspect.isShiftImmediate(word)
    return word & 0xff800000 == 0xd3000000 or word & 0xff800000 == 0x93000000
end

-- movz or movn: a literal made in a register.
function inspect.isMoveWide(word)
    return word & 0x1f800000 == 0x12800000
end

-- add xd, xn, #0.
function inspect.isAddZero(word)
    return word & 0xfffffc00 == 0x91000000
end

-- add xd, xn, xm, lsl #amount (a shifted register operand).
function inspect.isAddShifted(word)
    return word & 0xffe00000 == 0x8b000000 and (word >> 10) & 63 ~= 0
end

-- ccmp, by a register or an immediate.
function inspect.isConditionalCompare(word)
    return word & 0x7fe00400 == 0x7a400000
end

-- add xd, xn, #1.
function inspect.isAddImmediateOne(word)
    return word & 0xfffffc00 == 0x91000400
end

-- stp of two 64-bit registers at a signed offset.
function inspect.isStorePair(word)
    return word & 0xffc00000 == 0xa9000000
end

-- b: an unconditional branch.
function inspect.isBranch(word)
    return word & 0xfc000000 == 0x14000000
end

-- bl: a call.
function inspect.isBranchLink(word)
    return word & 0xfc000000 == 0x94000000
end

-- mov x0, xn (orr x0, xzr, xn).
function inspect.isMoveToFirst(word)
    return word & 0xffe0ffff == 0xaa0003e0
end

-- mov x16, xn (orr x16, xzr, xn).
function inspect.isMoveToScratch(word)
    return word & 0xffe0ffff == 0xaa0003f0
end

local only = {}
for _, name in ipairs(arg) do
    only[name] = true
end
local tool = bridge()
local passed, failed = 0, 0
for _, case in ipairs(cases(inspect)) do
    if next(only) == nil or only[case.name] then
        for _, spill in ipairs(case.spill == false and {false} or {false, true}) do
            local label = case.name .. (spill and " (spill)" or "")
            local ok, problem = pcall(function()
                local codes, order = select(case.text, spill, case.inline)
                local entry = case.entry or order[#order]
                local image, words = bundle(codes, order, entry, case.runs[1] and #case.runs[1].args or 0)
                if os.getenv("NUPP_S0_DISASSEMBLE") == "1" and not spill then
                    disassemble(case.name, words)
                end
                if case.check and not spill then
                    case.check(codes)
                end
                local path = OUT .. "/" .. case.name .. ".bundle"
                write(path, image)
                for _, run in ipairs(case.runs) do
                    local values = {0}
                    for _, value in ipairs(run.args) do
                        values[#values + 1] = value
                    end
                    write(path .. ".in", le(values, 8))
                    os.remove(path .. ".out")
                    local status, text = shell(
                        quote(tool) .. " " .. quote(path) .. " " .. quote(path .. ".in") .. " " .. quote(path .. ".out")
                    )
                    local bytes = read(path .. ".out")
                    assert(status == 0 and bytes and #bytes == 16, "bridge " .. tostring(status) .. " " .. text)
                    local value = word64(bytes, 1)
                    assert(
                        value == run.result,
                        ("(%s) gave %d, expected %d"):format(table.concat(run.args, ", "), value, run.result)
                    )
                end
            end)
            if ok then
                passed = passed + 1
            else
                failed = failed + 1
                print("FAIL " .. label .. ": " .. tostring(problem))
            end
        end
    end
end
-- Where control can go after the instruction at `index` (1-based) of
-- `words`: nowhere for an indirect branch, a return or a trap, the target for
-- an unconditional branch, else the next word and any conditional target.
local function successors(words, index)
    local word = words[index]
    local function offset(low, size)
        local field = (word >> low) & ((1 << size) - 1)
        if field >= 1 << (size - 1) then
            field = field - (1 << size)
        end

        return index + field
    end
    if word & 0xfffffc1f == 0xd61f0000 or word & 0xfffffc1f == 0xd65f0000 or word & 0xffe0001f == 0xd4200000 then
        return {}
    end
    if word & 0xfc000000 == 0x14000000 then
        return {offset(0, 26)}
    end
    local targets = {index + 1}
    if word & 0xff000010 == 0x54000000 or word & 0x7e000000 == 0x34000000 then
        targets[2] = offset(5, 19)
    elseif word & 0x7e000000 == 0x36000000 then
        targets[2] = offset(5, 14)
    end

    return targets
end

-- The shortest path from the entry to an indirect branch (br): its length in
-- instructions and the loads and stores on it.
local function dispatchPath(words)
    local from, queue, head = {[1] = 0}, {1}, 1
    while queue[head] do
        local index = queue[head]
        head = head + 1
        if words[index] & 0xfffffc1f == 0xd61f0000 then
            local count, memory = 0, 0
            while index ~= 0 do
                count = count + 1
                if (words[index] >> 25) & 5 == 4 then
                    memory = memory + 1
                end
                index = from[index]
            end

            return count, memory
        end
        for _, target in ipairs(successors(words, index)) do
            if words[target] and from[target] == nil then
                from[target] = index
                queue[#queue + 1] = target
            end
        end
    end

    return nil, nil
end

-- The real handlers, selected from their IR, held to their budgets.
local loader = require("handlerload")
for _, handler in ipairs(dofile(ROOT .. "/tests/core/s0/budgets.lua")) do
    if next(only) == nil or only[handler.name] then
        local ok, problem = pcall(function()
            local f = loader.load(assert(read(ROOT .. "/tests/core/s0/handlers/" .. handler.name .. ".json")))
            -- The small leaves it calls, as the selector inlines them.
            inliner.all(f, function(symbol)
                local text = read(ROOT .. "/tests/core/s0/handlers/callees/" .. symbol .. ".json")
                return text and loader.load(text) or nil
            end)
            local target = selector.target()
            local a = allocate.run(f, target)
            check.run(f, target, a)
            local words = selector.run(f, a).words
            if os.getenv("NUPP_S0_IR") == "1" then
                for block, start in ipairs(f.blockStart) do
                    local parameters = {}
                    for p = f.firstParam[block], f.firstParam[block] + f.nparams[block] - 1 do
                        parameters[#parameters + 1] = "v" .. f.params[p] .. (a.used[f.params[p]] == false and "" or "*")
                    end
                    print(("block%d(%s):"):format(block, table.concat(parameters, ", ")))
                    for at = start, f.blockEnd[block] do
                        local args = {}
                        for p = f.firstArg[at], f.firstArg[at] + f.nargs[at] - 1 do
                            args[#args + 1] = "v" .. f.args[p]
                        end
                        for e = f.firstEdge[at], f.firstEdge[at] + f.nedges[at] - 1 do
                            local edge = {}
                            for p = 0, f.edgeNargs[e] - 1 do
                                edge[#edge + 1] = "v" .. f.edgeArgs[f.edgeFirstArg[e] + p]
                            end
                            args[#args + 1] = ("block%d(%s)"):format(f.edgeTarget[e], table.concat(edge, ", "))
                        end
                        print(
                            ("  %3d %s%s %s imm %d aux %d%s"):format(
                                at,
                                f.result[at] ~= 0 and ("v" .. f.result[at] .. " = ") or "",
                                ir.opNames[f.op[at]],
                                table.concat(args, ", "),
                                f.imm[at],
                                f.aux[at],
                                a.saveSlot[f.result[at]] and a.saveSlot[f.result[at]] > 0 and " saved" or ""
                            )
                        )
                    end
                end
            end
            if os.getenv("NUPP_S0_DISASSEMBLE") == "1" then
                disassemble(handler.name, words)
            end
            local count, memory = dispatchPath(words)
            assert(count, "no path reaches the dispatch")
            local clang = handler.clang and ("clang %d/%d"):format(handler.clang[1], handler.clang[2]) or "no oracle"
            print(("%-9s %3d/%-3d %s, %d words in all"):format(handler.name, count, memory, clang, #words))
            assert(
                count <= handler.budget[1] and memory <= handler.budget[2],
                ("over budget %d/%d"):format(handler.budget[1], handler.budget[2])
            )
        end)
        if ok then
            passed = passed + 1
        else
            failed = failed + 1
            print("FAIL " .. handler.name .. ": " .. tostring(problem))
        end
    end
end
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
