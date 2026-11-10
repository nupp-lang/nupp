-- Lua twin of catalog-output-print.nupp.

-- print writes its values' text separated by tabs, then a newline.
print("hello", 42, 1.5, true, nil, false)
print()
print(("x"):rep(3), 10 // 3, -0.0, 1e100, 9007199254740992.0)
local count = 0
for i = 1, 3 do
    print("line", i)
    count = count + i
end
return count
