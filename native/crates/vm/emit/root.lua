-- Emit the root CLI image from a checkout with whichever compiler runs this:
-- the LuaJIT-built one seeds a checkout with no VM compiler yet.
--   nupp run native/crates/vm/emit/root.lua ROOT OUT
local project = require("nupp.tools.vm.project")
local root, out = assert(arg[1], "checkout root"), assert(arg[2], "output image")
local image = project.emit(root, "nupp.tools.vm.root", project.ROOT_EXTRAS, nil, false)
local file = assert(io.open(out, "wb"))
file:write(image)
file:close()
