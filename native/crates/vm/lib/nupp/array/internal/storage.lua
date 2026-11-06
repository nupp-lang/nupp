-- VM and native-core arrays share the managed storage implementation.
local _DYNAMIC_REQUIRES = [[
@requires-dynamically nupp.runtime.provider.arraystorage
@requires-dynamically nupp.vm.arraylayout
]]
local providerModule = table.concat({"nupp", "runtime", "provider", "arraystorage"}, ".")

return require(providerModule)
