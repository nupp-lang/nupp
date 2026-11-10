-- Lua twin of catalog-tables-sort.nupp.

-- table.sort by `<` and by a comparator, over integers, floats and strings.
-- Strings order byte by byte under `<` and `<=` too.
local nums = {5, 3, 9, 1, 7, 2, 8, 6, 4, 10, 0}
table.sort(nums)
local words = {"pear", "apple", "fig", "banana", "date"}
table.sort(words)
local down = {4, 1, 3, 5, 2, 6}
table.sort(down, function(a, b)
    return a > b
end)
local calls = 0
local byLength = {"ccc", "a", "dddd", "bb", "eeeee"}
table.sort(byLength, function(a, b)
    calls = calls + 1
    return #a < #b
end)
local mixed = {2.5, 1, 3, 0.5, 2}
table.sort(mixed)
local single = {1}
table.sort(single)
local empty = {}
table.sort(empty)
local score = 0
for i, n in ipairs(nums) do
    score = score + i * n
end
score = score * 100
for i, n in ipairs(down) do
    score = score + i * n
end
score = score * 2
if table.concat(words, ",") == "apple,banana,date,fig,pear" then
    score = score + 1
end
score = score * 2
if table.concat(byLength, ",") == "a,bb,ccc,dddd,eeeee" and calls > 0 then
    score = score + 1
end
score = score * 2
if mixed[1] == 0.5 and mixed[2] == 1 and mixed[3] == 2 and mixed[5] == 3 then
    score = score + 1
end
score = score * 2
if single[1] == 1 and #empty == 0 then
    score = score + 1
end
score = score * 8
if "apple" < "banana" and "ab" <= "ab" and not ("b" < "ab") then
    score = score + 4
end
if "abc" > "abb" and "" < "a" and not ("ab" <= "a") then
    score = score + 2
end
if "a" >= "a" and not ("ab" < "ab") then
    score = score + 1
end
return score
