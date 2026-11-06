-- Lua twin of catalog-gc-exit.nupp.
local alive = {}

local function marked(holder)
    for i = 1, 2 do
        holder[i] = setmetatable({}, {
            __gc = function()
                print("closed", i)
            end
        })
    end
end

marked(alive)
print("exiting")
os.exit(4, true)
print("never")

return 0
