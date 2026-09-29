local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local M = {}

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()
    return text
end

function M.publicHeaderLinksAndRunsAgainstTheSelectedCdylib()
    local pipe = assert(io.popen("'" .. ROOT:gsub("'", "'\\''") .. "/scripts/test-rust-abi' 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))
    assert(status == 0, output)
end

-- Symbols the pinned bundle names that were deleted before this check existed.
-- Each is declared in a cdef the bundle never reaches, which is the only reason
-- its deletion was harmless; nothing may join this list.
local REMOVED_BEFORE_THE_CHECK = {
    nuppNativeProcessAbandonedTotal = true,
}

-- The pinned stage-zero compiler loads this checkout's freshly built provider,
-- so the provider may only grow. The ABI version stays the one the bundle
-- checks for exactly, and every provider symbol the bundle names is still
-- declared: a deleted one breaks a cold build the moment the bundle reaches it,
-- and nothing but the bundle's own text says whether it can.
function M.theProviderKeepsWhatThePinnedStageZeroNames()
    local pipe = assert(io.popen(("cd %s && ./scripts/toolchain stage0 2>/dev/null"):format(quote(ROOT))))
    local path = pipe:read("*a"):match("([^\r\n]+)%s*$")
    pipe:close()
    assert(path, "no stage-zero compiler; run scripts/toolchain stage0")
    local bundle = read(assert(path:match("^(.*)[/\\][^/\\]+$")) .. "/verified.lua")
    local header = read(ROOT .. "/native/include/nupp_native.h")

    local required = assert(bundle:match("\nconst ABI_VERSION = (%d+)\n"), "the bundle checks no ABI version")
    local provided = assert(header:match("#define NUPP_NATIVE_ABI_VERSION (%d+)u"), "the header has no ABI version")
    assert(required == provided, ("the pinned stage zero needs ABI %s and the header says %s"):format(required, provided))

    local declared = {}
    for name in header:gmatch("NUPP_NATIVE_EXPORT[^;(]-([%w_]+)%s*%(") do
        declared[name] = true
    end
    local missing, seen = {}, {}
    for name in bundle:gmatch("[%w_]+") do
        if name:match("^nuppNative") and not seen[name] then
            seen[name] = true
            if not declared[name] and not REMOVED_BEFORE_THE_CHECK[name] then
                missing[#missing + 1] = name
            end
        end
    end
    table.sort(missing)
    assert(next(seen), "the bundle names no provider symbol, so this check reads the wrong text")
    assert(#missing == 0, "the pinned stage zero names provider symbols the header lost: " .. table.concat(missing, ", "))
end

return M
