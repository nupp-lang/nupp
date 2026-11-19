-- Emit code and unwind from the same checked S0 build. The host cross-link
-- smoke consumes these exact bytes without running the resulting executable.
local builder = require("nupp.core.win64leaf")
local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
local directory = assert(arg[1], "output directory required")
local module = "nupp.core.win64leafunits"
local path = root .. "/tests/core/units/nupp/core/win64leafunits.nupp"
local include = {"tests/core/units"}
local code, entryBytes, unwind
if arg[2] == "page-size" then
    code, entryBytes, unwind = builder.buildPageSize(root, include, module, path, "startupPageSize")
    local ok, failure = pcall(builder.buildPageSize, root, include, module, path, "startupWrongSymbol")
    assert(not ok and tostring(failure):find("expected the exact page size import", 1, true))
else
    assert(arg[2] == nil, "unexpected Win64 entry")
    code, entryBytes, unwind = builder.buildCall(root, include, module, path, "callWord", "addWord")
end
assert(entryBytes > 0 and entryBytes < #code and #unwind == 8)

local function write(name, bytes)
    local output = assert(io.open(directory .. "/" .. name, "wb"))
    assert(output:write(bytes))
    assert(output:close())
end

write("win64-call.bin", code)
write("win64-unwind.bin", unwind)
write(
    "win64-call.S",
    (
        [[
.text
.globl nupp_core_win64_entry
.def nupp_core_win64_entry; .scl 2; .type 32; .endef
nupp_core_win64_entry:
.incbin "win64-call.bin"
.set nupp_core_win64_end, nupp_core_win64_entry + %d

.section .xdata,"dr"
.p2align 2
nupp_core_win64_unwind:
.incbin "win64-unwind.bin"

.section .pdata,"dr"
.p2align 2
.rva nupp_core_win64_entry, nupp_core_win64_end, nupp_core_win64_unwind
]]
    ):format(entryBytes)
)
local tail = arg[2] == "page-size" and "name" or "callee"
print(("checked Win64 call: %d entry bytes, %d %s bytes"):format(entryBytes, #code - entryBytes, tail))
