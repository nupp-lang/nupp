-- Run by `nupp test`, which builds the default target first, so this requires
-- the compiled module rather than the source it came from.
local greeting = require("greeting")

assert(greeting.forName("Nupp") == "Hello, Nupp!")

print("ok")
