-- Lua twin of catalog-legacy-globals.nupp, under a Lua with no `jit`.
local unpackAny = table.unpack
local a, b, c = unpackAny({1, 2, 3})
local platform = tostring(jit and jit.os)

return a * 100 + b * 10 + c + (platform == "nil" and 1000 or 0)
