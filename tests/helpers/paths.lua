-- Repository paths stay independent of a suite's subject directory.
local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local tests = assert(source:match("^(.*)/helpers/paths%.lua$"))
local fs = require("nupp.compiler.fs")
return {tests = tests, absoluteTests = fs.absolute(tests), root = fs.absolute(tests .. "/..")}
