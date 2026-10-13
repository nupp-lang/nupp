-- Seed the project compiler once with the existing Nupp host. Subsequent
-- compiler-image rebuilds run entirely on nupp-vm.
local project = require("nupp.tools.vm.project")
io.write(project.rebuild(assert(arg[1], "compiler source root"), true))
