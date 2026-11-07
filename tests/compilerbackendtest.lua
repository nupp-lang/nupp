local native = require("nupp.compiler.native")
local surface = require("nupp.compiler.standardsurface")
local M = {}

function M.compressionFacadeRequiresItsCatalogBackend()
    local feature = assert(native.feature("native.compression"))
    assert(#feature.facades == 1 and feature.facades[1] == "nupp.compression")
    assert(native.backend("nupp.compression") == feature.runtimeModule)
    assert(native.forModule(feature.runtimeModule) == "native.compression")
end

function M.backendPrerequisiteDoesNotChangeImportEffects()
    assert(native.forModule("nupp.compression") == nil)
    assert(surface.classify("nupp.compression").kind == "common")
    assert(native.forModuleMember("binary", "compress") == "native.compression")
    assert(next(native.expand({})) == nil)
    local effects = native.expand({["native.compression"] = true})
    assert(effects["runtime.native"] and effects["runtime.spanview"] and effects["stdlib.io"])
end

function M.backendQueryDoesNotInferOptionalAlternatives()
    assert(native.backend("nupp.runtime.bindings.clock") == nil)
    assert(native.backend("nupp.runtime.standardio") == nil)
    assert(native.backend("nupp.digest.checksum") == nil)
    assert(native.backend("nupp.compression.contracts") == nil)
    assert(native.backend("unregistered.facade") == nil)
end

return M
