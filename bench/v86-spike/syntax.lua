-- Exercise the extensions in the exact pinned upstream runtime.
local body = assert(
    loadstring(
        [[
const mask = 0xff
local value = 1_000
value += 24
local absent = nil
local total = 0
for i = 1, 5 do
    if i == 3 then continue end
    total += i
end
return (value >> 2) & mask, absent?.field ?? 42,
       !false && (total != 0 || false) ? total : 0
]]
    )
)
local a, b, c = body()
assert(a == 0 and b == 42 and c == 12)
return true
