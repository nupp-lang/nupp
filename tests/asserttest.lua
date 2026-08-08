local test = require("assert")
local M = {}

function M.describesDifferentValues()
   local err = test.raises(function() test.equal("actual", "expected") end)
   test.matches(err, 'expected "expected", got "actual"')
end

function M.describesFalsyAssertions()
   local err = test.raises(function() test.assert(nil) end)
   test.matches(err, "expected a truthy value, got nil")
end

function M.keepsCallerMessage()
   local err = test.raises(function() test.equal(2, 1, "numbers differ") end)
   test.matches(err, "numbers differ")
end

function M.identifiesSkippedTests()
   local ok, skip = pcall(function() test.skip("needs a network connection") end)
   test.assert(not ok)
   test.assert(test.isSkip(skip))
   test.equal(test.skipReason(skip), "needs a network connection")
end

return M
