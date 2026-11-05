local test = require("assert")
local envMod = require("nupp.compiler.project.env")
local surface = require("nupp.compiler.standardsurface")
local M = {}

function M.providerHelpersKeepTheirTypesOutsideTheCompilerCheckout()
    local env = envMod.new("/private/tmp/nupp-provider-helper-consumer", {
        config = {include = {"src"}},
        typeRoots = {},
        cache = false,
    })
    for _, helper in ipairs({
        {name = "io.internal.boundedcache", path = "/io/internal/boundedcache.nupp", member = "create"},
        {name = "nupp.workers.internal.support", path = "/nupp/workers/internal/support.nupp", member = "pack"},
    }) do
        test.eq(env.bundledImplementation(helper.name), helper.path)
        test.eq(surface.classify(helper.name).kind, "common")
        test.eq(env.bundledInternal(helper.name), true, "carrying a helper keeps it private")
        local cold = assert(env.resolveModuleExports(env, helper.name), helper.name .. " has checked carried exports")
        test.eq(cold.values[helper.member].tag, "func")
        local warm = assert(env.resolveModuleExports(env, helper.name))
        test.eq(warm, cold, "warm resolution keeps the checked export identity")
    end
    local paths = assert(env.resolveModuleExports(env, "io.internal.path"))
    test.eq(paths.values.newpath.tag, "func", "the Path owner resolves through its private helper")
    local native = assert(env.resolveModuleExports(env, "nupp.runtime.provider.workers"))
    test.eq(native.values.openscope.tag, "func", "the native provider resolves through its private helper")
end

return M
