local test = require("assert")
local aot = require("nupp.tools.vm.aotparts")
local M = {}
local DIGEST = string.rep("a", 64)
local TABLE = "nupp_aot_table_v1"
local RENAMED = "nupp_aot_table_01"

local function rejected(action)
    test.eq(pcall(action), false)
end

local function u16(value)
    return string.char(value % 256, math.floor(value / 256) % 256)
end

local function u32(value)
    return u16(value % 65536) .. u16(math.floor(value / 65536))
end

local function u64(value)
    return u32(value % 4294967296) .. u32(math.floor(value / 4294967296))
end

local function zeros(count)
    return string.rep("\0", count)
end

function M.partitionsNamesTogetherAndReplicatesRequiredCode()
    local functions = aot.describe(
        table.concat(
            {
                "function alpha 0 0 2 0 :v",
                "  Nil 0",
                "function same 1 0 2 0 :v",
                "  Add 0 0 0",
                "function same 2 0 2 0 :v",
                "  Add 0 0 0",
                "function vector 3 0 2 0 :v",
                "  VAny 0 0",
                "",
            },
            "\n"
        )
    )
    local groups = aot.partition(functions, 3)
    local owners, seen = {}, {}
    for _, group in ipairs(groups) do
        local names = "," .. group.selector .. ","
        test.eq(names:find(",vector,", 1, true) ~= nil, true)
        test.eq(group.owned[1], group.owned[2], "equal names cannot be split")
        for _, fid in ipairs(group.fids) do
            seen[fid] = (seen[fid] or 0) + 1
            if group.owned[fid] then
                owners[fid] = (owners[fid] or 0) + 1
            end
        end
    end
    for fid = 0, 3 do
        test.eq(owners[fid], 1)
    end
    test.eq(seen[3], 3)
    test.eq(seen[0], 1)
end

function M.refusesAmbiguousSelectorsAndInvalidCatalogs()
    rejected(function()
        aot.describe("function f 1 0 0 0 :v\n")
    end)
    rejected(function()
        aot.partition({{name = "a,b", fid = 0, weight = 1}}, 2)
    end)
    rejected(function()
        aot.partition({}, 5)
    end)
    rejected(function()
        aot.partition({}, 1.5)
    end)
end

function M.addsBoundedWavesForShortProcessEnvironments()
    local functions = {}
    for fid = 0, 15 do
        functions[#functions + 1] = {fid = fid, name = ("function_%03d"):format(fid), weight = 1}
    end
    local groups = assert(aot.plan(functions, 4, 35))
    test.eq(#groups, 8)
    local owners = {}
    for _, group in ipairs(groups) do
        test.eq(#group.selector < 35, true)
        for fid in pairs(group.owned) do
            test.eq(owners[fid], nil)
            owners[fid] = true
        end
    end
    for fid = 0, 15 do
        test.eq(owners[fid], true)
    end
    rejected(function()
        aot.plan(functions, 5)
    end)
end

function M.requiresExactImageAndFunctionManifest()
    local text = "runtime-abi\t4\nimage-sha256\t" .. DIGEST .. "\nfunctions\t3\n0\tnupp_aot_0\n2\tnupp_aot_2\n"
    aot.manifest(text, DIGEST, 3, {0, 2})
    rejected(function()
        aot.manifest(text, string.rep("b", 64), 3, {0, 2})
    end)
    rejected(function()
        aot.manifest(text, DIGEST, 3, {0, 1})
    end)
    rejected(function()
        aot.manifest(text .. "2\tnupp_aot_2\n", DIGEST, 3, {0, 2})
    end)
end

function M.validatesRootMapsAndRefusesMalformedRecords()
    local row = u32(2) .. u32(32) .. u32(1) .. u32(8) .. u32(16) .. u32(2) .. u32(0) .. u32(8)
    local blob = u32(1) .. row
    test.eq(aot.maps(blob, {2})[2], row)
    rejected(function()
        aot.maps(blob:sub(1, -2), {2})
    end)
    rejected(function()
        aot.maps(blob .. u32(0), {2})
    end)
    rejected(function()
        aot.maps(blob, {1})
    end)
    rejected(function()
        aot.maps(blob:sub(1, -5) .. u32(16), {2})
    end)
end

local function macho()
    local strings = "\0_" .. TABLE .. "\0"
    local header = u32(0xfeedfacf) .. u32(0x100000c) .. u32(0) .. u32(1) .. u32(1) .. u32(24) .. u32(0) .. u32(0)
    local command = u32(2) .. u32(24) .. u32(56) .. u32(1) .. u32(72) .. u32(#strings)
    local symbol = u32(1) .. string.char(15, 1) .. u16(0) .. u64(0)

    return header .. command .. symbol .. strings
end

local function elf()
    local strings = "\0" .. TABLE .. "\0"
    local header = "\127ELF\2\1\1" .. zeros(
        9
    ) .. u16(
        1
    ) .. u16(
        183
    ) .. u32(1) .. u64(0) .. u64(0) .. u64(64) .. u32(0) .. u16(64) .. u16(0) .. u16(0) .. u16(64) .. u16(3) .. u16(0)
    local symbols = u32(0) .. u32(2) .. u64(0) .. u64(0) .. u64(256) .. u64(48) .. u32(2) .. u32(1) .. u64(8) .. u64(24)
    local strtab = u32(
        0
    ) .. u32(3) .. u64(0) .. u64(0) .. u64(304) .. u64(#strings) .. u32(0) .. u32(0) .. u64(1) .. u64(0)
    local symbol = u32(1) .. string.char(0x11, 0) .. u16(1) .. u64(0) .. u64(0)

    return header .. zeros(64) .. symbols .. strtab .. zeros(24) .. symbol .. strings
end

local function coff()
    local strings = u32(#TABLE + 5) .. TABLE .. "\0"
    local header = u16(0x8664) .. u16(0) .. u32(0) .. u32(20) .. u32(1) .. u16(0) .. u16(0)
    local symbol = u32(0) .. u32(4) .. u32(0) .. u16(1) .. u16(0) .. string.char(2, 0)
    return header .. symbol .. strings
end

function M.renamesOnlyRequestedSymbolBytesAcrossAllObjectFormats()
    for _, make in ipairs({macho, elf, coff}) do
        local original = make()
        local changed = aot.rename(original, {[TABLE] = RENAMED})
        test.eq(#changed, #original)
        test.eq(changed, (original:gsub(TABLE, RENAMED)))
        rejected(function()
            aot.rename(original:sub(1, -2), {[TABLE] = RENAMED})
        end)
        rejected(function()
            aot.rename(original, {missing = RENAMED})
        end)
        rejected(function()
            aot.rename(original, {[TABLE] = "short"})
        end)
    end
end

function M.refusesExecutableOrUnknownObjectContainers()
    rejected(function()
        aot.rename("not an object", {[TABLE] = RENAMED})
    end)
    local original = elf()
    rejected(function()
        aot.rename(original:sub(1, 16) .. u16(2) .. original:sub(19), {[TABLE] = RENAMED})
    end)
end

function M.emitsMergedSidecarWithPortableEscaping()
    local text = aot.sidecar(DIGEST, {0, 3}, 'C:/a "quoted"/maps\nfile')
    test.eq(text:find('fn nupp_aot_0();', 1, true) ~= nil, true)
    test.eq(text:find('fn nupp_aot_3();', 1, true) ~= nil, true)
    test.eq(text:find('\\"quoted\\"', 1, true) ~= nil, true)
    test.eq(text:find('\\u{a}', 1, true) ~= nil, true)
end

return M
