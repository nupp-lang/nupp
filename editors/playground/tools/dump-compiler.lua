local path = assert(arg[1], "compiler bundle is required")
local bytecode = string.dump(assert(loadfile(path, "tW")), "sd")
assert(#bytecode > 1024 and #bytecode <= 7 * 1024 * 1024, "invalid compiler bytecode extent")
io.write(bytecode)
