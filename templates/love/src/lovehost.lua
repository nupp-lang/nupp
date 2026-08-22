-- The subset of LÖVE used by this template. This adapter returns LÖVE's global
-- value under an ordinary module name, so it generates no replacement runtime.

---@class LoveGraphics
---@field setBackgroundColor fun(red: number, green: number, blue: number)
---@field setColor fun(red: number, green: number, blue: number)
---@field rectangle fun(mode: string, x: number, y: number, width: number, height: number)

---@class Love
---@field graphics LoveGraphics
---@field load fun()
---@field update fun(elapsed: number)
---@field draw fun()

---@type Love
local love = assert(rawget(_G, "love"), "LÖVE did not install its global API")

return love
