-- The shipped normaliser, re-exported so a build target can compile it. Plain
-- Lua, because the module is internal to the `nupp` namespace and only `.lua`
-- may reach it directly.
local pathtext = require("nupp.io.path.pathtext")
return {normalize = pathtext.normalize}
