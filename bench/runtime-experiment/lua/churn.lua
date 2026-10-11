local t = os.clock(); local r = {x = 0}
for i = 1, 5000000 do r.x = r.x + i end
print(string.format("churn5m\t%.6f", os.clock() - t)); assert(r.x == 12500002500000)
