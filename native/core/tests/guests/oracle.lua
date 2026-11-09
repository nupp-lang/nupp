-- Differential testing against Lua 5.5: generated programs in the core's
-- subset (generate.lua) run on the standalone core and on the reference
-- interpreter, and their checksums must agree word for word. One process
-- builds the guest runtime once and compiles each program against it.
--
--   cd native/core/tests/guests && NUPP_COMPILER_ROOT=$PWD/../../../.. \
--     NUPP_LUA_REFERENCE=path/to/lua ../../../../bin/nupp run oracle.lua [COUNT] [FIRST-SEED]
--
-- Each disagreement leaves its program and twin under build/core-guests/generated.
local producer = require("nupp.core.guestprogramproducer")
local sharedcache = require("nupp.core.sharedcache")
local generate = require("generate")
local ROOT = assert(os.getenv("NUPP_COMPILER_ROOT"), "set NUPP_COMPILER_ROOT to the checkout root")
local LUA = assert(os.getenv("NUPP_LUA_REFERENCE"), "set NUPP_LUA_REFERENCE to a Lua 5.5 interpreter")
local OUT = ROOT .. "/build/core-guests/generated"
local STAGED = ROOT .. "/build/core-guest-programs/source/nupp/core"
local BRIDGE = ROOT .. "/build/core-bridge/debug/nupp-core"
local SCRATCH = 1048576

local function quote(value)
    return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function shell(command)
    local pipe = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local output = pipe:read("*a")
    pipe:close()
    return tonumber(output:match("__exit__:(%d+)%s*$")), (output:gsub("__exit__:%d+%s*$", ""))
end

local function write(path, bytes)
    local file = assert(io.open(path, "wb"))
    file:write(bytes)
    file:close()
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

local function u64(value)
    local out = {}
    for at = 0, 7 do
        out[at + 1] = string.char((value >> (at * 8)) & 255)
    end

    return table.concat(out)
end

local function u32(value)
    local out = {}
    for at = 0, 3 do
        out[at + 1] = string.char((value >> (at * 8)) & 255)
    end

    return table.concat(out)
end

local function fromHex(text)
    return (text:gsub("..", function(pair)
        return string.char(tonumber(pair, 16))
    end))
end

local function bundleOf(selected)
    local words = {}
    for index, word in ipairs(selected.words) do
        words[index] = u32(word)
    end
    local code, data = table.concat(words), fromHex(selected.dataHex)

    return "NUPPCORE" .. u64(
        1
    ) .. u64(1) .. u64(selected.entry) .. u64(#code) .. u64(#data) .. u64(SCRATCH) .. u64(1) .. u64(0) .. code .. data
end

-- The reference result as the core's word: integers as 48-bit immediates.
local function reference(path)
    local status, output = shell(
        quote(
            LUA
        ) .. " -e " .. quote(
            "local ok, v = pcall(dofile, " .. (
                "%q"
            ):format(
                path
            ) .. ") " .. "if not ok then io.write('E', tostring(v)) else io.write(string.format('I%d', v)) end"
        )
    )
    assert(status == 0, output)
    if output:sub(1, 1) == "E" then
        return nil, output
    end
    local value = math.tointeger(tonumber(output:sub(2)))

    return 0x7FFF000000000000 | (value & 0xFFFFFFFFFFFF)
end

local count = tonumber(arg[1] or "50")
local first = tonumber(arg[2] or "1")
os.execute("mkdir -p " .. quote(OUT) .. " " .. quote(STAGED))
local agreed, failed, started = 0, 0, os.time()
for seed = first, first + count - 1 do
    local name = "generated" .. seed
    local nupp, lua = generate.program(seed, 10 + seed % 12)
    write(OUT .. "/" .. name .. ".nupp", nupp)
    -- The generated module is nupp.core.<name>, as the shared checker resolves it.
    write(STAGED .. "/" .. name .. ".nupp", nupp)
    write(OUT .. "/" .. name .. ".lua", lua)
    local expected, problem = reference(OUT .. "/" .. name .. ".lua")
    local ok, selected = pcall(
        producer.selectUnits,
        name,
        "normal",
        tostring(SCRATCH),
        sharedcache.directory("kernels")
    )
    local verdict
    if expected == nil then
        verdict = "reference raised: " .. tostring(problem)
    elseif not ok then
        verdict = "core build failed: " .. tostring(selected)
    else
        write(OUT .. "/" .. name .. ".bundle", bundleOf(selected))
        local output = OUT .. "/" .. name .. ".out"
        os.remove(output)
        local status, text = shell(
            ("%s %s /dev/null %s"):format(quote(BRIDGE), quote(OUT .. "/" .. name .. ".bundle"), quote(output))
        )
        local got = read(output)
        if status ~= 0 then
            verdict = "core refused: " .. text:gsub("%s+$", "")
        elseif got ~= u64(expected) then
            verdict = "checksum differs"
        end
    end
    if verdict then
        failed = failed + 1
        print(("FAIL %s: %s"):format(name, verdict:sub(1, 300)))
    else
        agreed = agreed + 1
        os.remove(OUT .. "/" .. name .. ".nupp")
        os.remove(STAGED .. "/" .. name .. ".nupp")
        os.remove(OUT .. "/" .. name .. ".lua")
        os.remove(OUT .. "/" .. name .. ".bundle")
        os.remove(OUT .. "/" .. name .. ".out")
    end
end
print(("%d agreed, %d failed, %ds"):format(agreed, failed, os.time() - started))
os.exit(failed == 0 and 0 or 1)
