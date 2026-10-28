-- Test-only raw entry. The selected handler and its loaded-target tail are unchanged.
local arm = require("s0.arm64")
local M = {}

function M.build(code, count)
    assert(count >= 1 and count <= 64 and count % 1 == 0)
    assert(#code.fixupWord == 0 and code.frameBytes >= 0 and code.frameBytes <= 12288)
    local words = {}

    local function emit(word)
        words[#words + 1] = word
    end

    local function constant(reg, value)
        emit(arm.movz(64, reg, value, 0))
    end

    emit(arm.sub_imm(64, 31, 31, 192, 0))
    for reg = 19, 29, 2 do
        emit(arm.stp(64, reg, reg + 1, 31, (reg - 19) * 8, 0))
    end
    for reg = 8, 14, 2 do
        emit(arm.stp_fp(64, reg, reg + 1, 31, 96 + (reg - 8) * 8, 0))
    end
    emit(arm.str(8, 0, 31, 160));
    emit(arm.str(8, 1, 31, 168))
    constant(16, 1);
    emit(arm.str(8, 16, 1, 0))
    local invalid = {}
    for _, pair in ipairs({{0, 1}, {64, count * 2 + 6}, {72, 11}}) do
        emit(arm.ldr(8, 16, 0, pair[1]));
        emit(arm.cmp_imm(64, 16, pair[2], 0))
        invalid[#invalid + 1] = #words + 1;
        emit(arm.b_cond(1, 0))
    end
    emit(arm.ldr(8, 22, 0, 40))
    constant(0, 16384);
    emit(arm.ldr(8, 16, 22, 0));
    emit(arm.blr(16))
    local failed = #words + 1;
    emit(arm.cbz(64, 0, 0))
    emit(arm.str(8, 0, 31, 176))
    emit(arm.add_imm(64, 23, 0, 1, 1))
    emit(arm.ldr(8, 16, 31, 160));
    emit(arm.ldr(8, 17, 16, 56))
    for index = 0, 3 do
        emit(arm.ldr(8, 16, 17, index * 8));
        emit(arm.str(8, 16, 0, index * 8))
    end
    for index = 0, count * 2 + 1 do
        emit(arm.ldr(8, 16, 17, 32 + index * 8));
        emit(arm.str(8, 16, 0, 256 + index * 8))
    end
    local stopAddress = #words + 1;
    emit(arm.adr(16, 0))
    emit(arm.str(8, 16, 0, 2048))
    emit(arm.mov_reg(64, 2, 0))
    emit(arm.add_imm(64, 1, 2, 128, 0))
    emit(arm.add_imm(64, 3, 2, 192, 0))
    emit(arm.add_imm(64, 4, 2, 224, 0))
    emit(arm.add_imm(64, 5, 2, 2048, 0))
    emit(arm.add_imm(64, 0, 2, 256, 0))
    local invoke = #words + 1;
    emit(arm.bl(0))
    emit(arm.ldr(8, 16, 31, 168));
    emit(arm.ldr(8, 17, 31, 176))
    emit(arm.str(8, 31, 16, 0))
    for index = 0, 3 do
        emit(arm.ldr(8, 0, 17, index * 8));
        emit(arm.str(8, 0, 16, 8 + index * 8))
    end
    for index = 0, 5 do
        emit(arm.ldr(8, 0, 17, 1600 + index * 8))
        emit(arm.sub_reg(64, 0, 0, 17, 0))
        emit(arm.str(8, 0, 16, 40 + index * 8))
    end
    emit(arm.mov_reg(64, 0, 17));
    constant(1, 16384)
    emit(arm.ldr(8, 16, 22, 8));
    emit(arm.blr(16))
    local finish = #words + 1
    words[failed] = arm.cbz(64, 0, (finish - failed) * 4)
    for _, at in ipairs(invalid) do
        words[at] = arm.b_cond(1, (finish - at) * 4)
    end
    for reg = 8, 14, 2 do
        emit(arm.ldp_fp(64, reg, reg + 1, 31, 96 + (reg - 8) * 8, 0))
    end
    for reg = 19, 29, 2 do
        emit(arm.ldp(64, reg, reg + 1, 31, (reg - 19) * 8, 0))
    end
    emit(arm.add_imm(64, 31, 31, 192, 0));
    emit(arm.ret(30))
    local body = #words + 1
    for _, word in ipairs(code.words) do
        emit(word)
    end
    words[invoke] = arm.bl((body - invoke) * 4)
    words[stopAddress] = arm.adr(16, (#words + 1 - stopAddress) * 4)
    -- The stop target observes the physical ABI, including dispatch-table arg6.
    emit(arm.sub_imm(64, 6, 23, 1, 1))
    for reg = 0, 5 do
        emit(arm.str(8, reg, 6, 1600 + reg * 8))
    end
    constant(0, 0);
    emit(arm.ret(30))

    return words
end

function M.write(code, count, directory, digest)
    local words = M.build(code, count)
    local bytes = {}
    for _, word in ipairs(words) do
        bytes[#bytes + 1] = string.char(word & 255, (word >> 8) & 255, (word >> 16) & 255, (word >> 24) & 255)
    end
    local file = assert(io.open(directory .. "/code.bin", "wb"));
    file:write(table.concat(bytes));
    file:close()
    local data = assert(io.open(directory .. "/data.bin", "wb"));
    data:close()
    local manifest = assert(io.open(directory .. "/bundle.json", "wb"))
    manifest:write(
        '{"version":1,"architecture":"aarch64","layoutDigest":"'
        .. digest
        .. '","entry":0,"code":"code.bin","data":"data.bin","imports":["nupp_os_map_pages","nupp_os_unmap_pages"],"outputWords":11}\n'
    )
    manifest:close()
end

return M
