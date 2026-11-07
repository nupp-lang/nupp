-- Run the pinned compiler with the declaration data of the checkout it emits.
-- The seed's executable files stay unchanged; its reader still checks all source.
local bootstrap = {}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
end

local function extras(root)
    local source = read(root .. "/src/nupp/tools/vm/project.nupp")
    local expression = assert(source:match("project%.ROOT_EXTRAS%s*=%s*(.-)\n\n"), "root extras declaration required")
    local names = {}
    local rest = expression:gsub('"([%w%._,]+)"', function(value)
        names[#names + 1] = value
        return ""
    end):gsub("%.%.", "")
    assert(#names > 0 and rest:match("^%s*$"), "root extras must be literal module names")

    return table.concat(names)
end

function bootstrap.emit(root, output, additions)
    local modules = additions or extras(root)
    local manifest = assert(loadfile(root .. "/nupp.lua"))()
    local generated = require("nupp.compiler.vm.resources").source(root, manifest)
    local current = assert(loadstring(generated))()
    local carried = require("nupp.vm.cliResources")
    -- The checker may already retain this exact table. Rebind its contents,
    -- rather than installing a different table behind the cached reference.
    for key in pairs(carried) do
        carried[key] = nil
    end
    local count = 0
    for key, value in pairs(current) do
        assert(type(key) == "string" and type(value) == "string", "source resource expected")
        carried[key] = value
        count = count + 1
    end
    assert(count > 0, "compiler resources required")
    package.preload["nupp.embedded"] = function()
        return carried
    end
    assert(
        require(
            "nupp.compiler.bundled"
        ).source("/decls/prelude.d.nupp") == read(root .. "/src/nupp/compiler/decls/prelude.d.nupp"),
        "bootstrap prelude differs from source"
    )
    io.stderr:write("bootstrap declarations: ", tostring(count), " source resources\n")
    local image = require("nupp.tools.vm.project").emit(root, "nupp.tools.vm.root", modules)
    local file = assert(io.open(output, "wb"))
    file:write(image)
    file:close()
end

if arg and arg[1] == "emit" then
    bootstrap.emit(assert(arg[2]), assert(arg[3]), arg[4])
end

return bootstrap
