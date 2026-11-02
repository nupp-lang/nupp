-- Lua twin of catalog-strings-gsubfn.nupp.

-- string.gsub with a function replacement: it is called with the captures,
-- or the whole match without any, and its string or number answer replaces
-- the match; false or nil keeps it.
local upper = ("hello world"):gsub("%w+", function(word)
    return word:upper()
end)
local seen = 0
local swapped, swaps = string.gsub("a=1, b=22, c=333", "(%w+)=(%w+)", function(k, v)
    seen = seen + 1
    return v .. "=" .. k
end)
local kept = ("one two three"):gsub("%a+", function(word)
    if #word == 3 then
        return nil
    end
    return "<" .. word .. ">"
end)
local lengths = ("ab cde f"):gsub("%a+", function(word)
    return #word
end)
local limited, count = ("x x x x"):gsub("x", function(x)
    return "y"
end, 2)
local anchored = ("aaa"):gsub("^a", function(a)
    return "b"
end)
local empty = (""):gsub("z", function(z)
    return "q"
end)
local score = 0
if upper == "HELLO WORLD" then
    score = score + 1
end
if swapped == "1=a, 22=b, 333=c" and swaps == 3 and seen == 3 then
    score = score + 2
end
if kept == "one two <three>" then
    score = score + 4
end
if lengths == "2 3 1" then
    score = score + 8
end
if limited == "y y x x" and count == 2 then
    score = score + 16
end
if anchored == "baa" and empty == "" then
    score = score + 32
end
return score
