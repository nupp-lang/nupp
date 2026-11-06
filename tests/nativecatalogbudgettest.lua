local service = require("nupp.compiler.vm.nativeservice")
local M = {}

function M.checkedCatalogKeepsItsFiniteOwnerLimit()
    local directory = os.tmpname()
    os.remove(directory)
    assert(os.execute("mkdir -p '" .. directory .. "/nupp/core'") == 0)
    local name = "nupp.core.catalogbudgetfixture"
    local path = directory .. "/nupp/core/catalogbudgetfixture.nupp"
    local file = assert(io.open(path, "wb"))
    file:write("module " .. name .. "\n")
    for index = 1, service.MAX_OWNERS do
        file:write(("export function f%d(): uint64\n    return 0ULL\nend\n"):format(index))
    end
    file:close()
    local okay, problem = pcall(function()
        local fixtures = {{moduleName = name, path = path, include = directory}}
        local roots = {{name, "f1"}}
        local initial = service.buildUnits(fixtures, roots)
        local infrastructure = #service.owners(initial.catalog) - 1
        assert(infrastructure > 0 and infrastructure < service.MAX_OWNERS)
        for index = 2, service.MAX_OWNERS - infrastructure do
            roots[#roots + 1] = {name, "f" .. index}
        end
        local exact = service.buildUnits(fixtures, roots)
        assert(#service.owners(exact.catalog) == service.MAX_OWNERS)
        roots[#roots + 1] = {name, "f" .. (service.MAX_OWNERS - infrastructure + 1)}
        local accepted, refusal = pcall(service.buildUnits, fixtures, roots)
        assert(not accepted and tostring(refusal):find("service owner limit", 1, true), tostring(refusal))
    end)
    os.execute("rm -rf '" .. directory .. "'")
    if not okay then
        error(problem, 0)
    end
end

return M
