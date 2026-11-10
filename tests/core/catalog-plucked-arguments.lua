-- Lua twin of catalog-plucked-arguments.nupp, as main emits its calls: each
-- plucked field read from its source, nil in a skipped slot.
local function draw(x, y, color, scale)
    return x * 1000 + y * 100 + (color == nil and 0 or 10) + (scale or 0)
end

local position = {x = 1, y = 2, z = 3}
local sprite = {x = 4, y = 5, frame = 6}

return draw(position.x, position.y)
    + draw(sprite.x, sprite.y, "blue") * 10000
    + draw(position.x, position.y, nil, 7) * 100000000
