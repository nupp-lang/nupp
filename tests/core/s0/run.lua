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
local arm = require("s0lab.arm64")
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
local function select(text, spill)
    local codes, order = {}, {}
    for _, f in ipairs(reader.read(text)) do
        local target = selector.target()
        if spill then
            target.integerRegisters, target.floatRegisters = {}, {}
        end
        local a = allocate.run(f, target)
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
        "clang -c -arch arm64 -o " .. quote(OUT .. "/" .. name .. ".o") .. " " .. quote(OUT .. "/" .. name .. ".s")
        .. " && objdump -d --no-show-raw-insn " .. quote(OUT .. "/" .. name .. ".o")
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
inspect.isLoad = function(word)
    -- Loads and stores of general and FP registers: the load/store class.
    return word & 0x0a000000 == 0x08000000
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
                local codes, order = select(case.text, spill)
                local entry = case.entry or order[#order]
                local image, words = bundle(codes, order, entry, #case.runs[1].args)
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
print(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
