-- Lua twin of catalog-library-ranges.nupp.

-- string.reverse, string.rep with a separator, table.concat over a range
-- and with floats, and table.move within one table (both overlaps) and
-- into another.
local reversed = ("hello"):reverse()
local repeated = string.rep("ab", 3, ", ")
local once = ("x"):rep(1, "-")
local none = ("x"):rep(0, "-")
local words = {"a", "b", "c", "d"}
local middle = table.concat(words, "+", 2, 3)
local empty = table.concat(words, "+", 3, 2)
local numbers = {1, 2.5, 10.0}
local mixed = table.concat(numbers, " ")
local up = {1, 2, 3, 4, 5}
table.move(up, 1, 3, 3)
local down = {1, 2, 3, 4, 5}
table.move(down, 3, 5, 1)
local target = {0, 0}
local moved = table.move(up, 2, 4, 2, target)
local score = 0
if reversed == "olleh" and (""):reverse() == "" then
    score = score + 1
end
if repeated == "ab, ab, ab" and once == "x" and none == "" then
    score = score + 2
end
if middle == "b+c" and empty == "" and mixed == "1 2.5 10.0" then
    score = score + 4
end
if table.concat(up, ",") == "1,2,1,2,3" and table.concat(down, ",") == "3,4,5,4,5" then
    score = score + 8
end
if moved == target and table.concat(target, ",") == "0,2,1,2" then
    score = score + 16
end
return score
