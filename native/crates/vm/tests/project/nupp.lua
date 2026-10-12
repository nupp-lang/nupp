local roots = {}
for _, name in ipairs({"lib"}) do
    roots[#roots + 1] = name
end
return {include = roots}
