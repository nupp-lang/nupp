local state = require("helpers.providerstate")
local M = {}

function M.layoutOnlyLoadingDoesNotInitializeWorkgroupsOrProviders()
    local preloads = {}
    for _, name in ipairs({
        "nupp.gpu.operations",
        "nupp.runtime.bindings.gpu",
        "nupp.runtime.provider.nativegpu",
        "nupp.runtime.browser.webgpu.internal"
    }) do
        preloads[name] = function()
            error("layout loaded " .. name)
        end
    end
    local load = state.instance({["io.gpu"] = true}, nil, preloads)
    local gpu = load("io.gpu")
    local Make = gpu.Layout
    local shape, strides = {4, 4}, {4, 1}
    local rows = Make(shape, strides)
    shape[1], strides[1] = 99, 99
    local column = rows:subview({0, 2}, {4, 1}):transpose({2, 1})
    assert(rows.count == 16 and rows:dimensions()[1] == 4)
    assert(column.count == 4 and column:offset() == 2)
end

function M.factoriesRemainCallableThroughStoredReferences()
    local io = require("nupp.runtime.standardio")
    local read = io.Reader.of
    local write = io.Writer.of
    local create = io.Buffer.create
    local source = read("held factory")
    assert(source:read(4) == "held")
    source:close()
    local buffer = create("before")
    local destination = write(buffer)
    destination:write("after")
    destination:close()
    assert(buffer:getstring() == "after")
    buffer:close()
    local binary = require("binary")
    assert(binary.Digest ~= binary.Mac, "factory namespaces must not alias")
    local digest = binary.Digest.create
    local context = digest("sha256")
    context:write("abc")
    assert(context:hexdigest() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    local path = io.Path.of
    local value = path("src", "main.nupp")
    assert(value == path("src", "main.nupp"), "the path factory retains interning")
    assert(getmetatable(value) == io.Path, "the facade exports the actual Path declaration")
    assert(value:filename() == "main.nupp")
end

function M.pathDeclarationLoadsWithoutItsImplementation()
    local load = state.instance({["io.internal.pathtypes"] = true}, nil, {
        ["io.internal.path"] = function()
            error("loading a Path declaration loaded its implementation")
        end
    })
    local Path = load("io.internal.pathtypes").Path
    assert(type(Path.of) == "function")
end

return M
