-- Produces the differential oracle through the normal LuaJIT compiler entry.
-- The stock Lua host reads these bytes but never gains filesystem access.

local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.env")
local optimize = require("nupp.compiler.optimize")
local gen = require("nupp.compiler.gen")
local tree = require("nupp.compiler.lsp.tree")
local T = require("nupp.compiler.types")
local json = require("nupp.runtime.provider.lunajson")
local capabilities = require("nupp.compiler.capabilities")
local seamRegistry = require("nupp.runtime.seam.registry")

-- The dialect under test is `lua51`, generated with the same backend the
-- portable bundle installs -- `nupp.compiler.browser`'s own `BACKENDS`,
-- reconstructed here rather than exported, since it is what decides which
-- seams (`suspension` among them) checking and generation see as available.
-- An oracle built against no backend at all would agree with the portable
-- bundle only on the modules that need none.
local BROWSER_DESCRIPTOR = {
   name = "nupp.browser",
   module = "nupp.runtime.backend.browser",
   digest = "portable-browser-providers-3",
   seams = {},
}
local BACKENDS = {modules = {BROWSER_DESCRIPTOR}, seams = {}, byEffect = {},}
local BROWSER_SEAMS = {
   {"numeric.bitops", "nupp.runtime.provider.scalarbitops"},
   {"data.json", "nupp.runtime.provider.lunajson"},
   {"suspension", "nupp.runtime.provider.browsersuspension"},
   {"io.uri", "nupp.runtime.provider.browseruri"},
   {"host.http", "nupp.runtime.provider.browserhttp"},
   {"host.time", "nupp.runtime.provider.browsertime"},
   {"host.browser_crypto", "nupp.runtime.provider.browsercrypto"},
   {"host.browser_storage", "nupp.runtime.provider.browserstorage"},
   {"host.workers", "nupp.runtime.provider.browserworkers"},
   {"data.sha256", "nupp.runtime.provider.browsercrypto"},
   {"crypto.hmac_sha256", "nupp.runtime.provider.browsercrypto"},
   {"data.uuid", "nupp.runtime.provider.browsercrypto"},
}
for _, values in ipairs(BROWSER_SEAMS) do
   local contract = seamRegistry.get(values[1])
   local selected = {
      name = contract.name,
      version = contract.version,
      effect = contract.effect,
      effects = contract.effects,
      binding = contract.binding,
      runtimeModule = values[2],
      backend = "nupp.browser",
      module = "nupp.runtime.backend.browser",
      modules = contract.modules,
      exports = contract.exports,
   }
   BROWSER_DESCRIPTOR.seams[#BROWSER_DESCRIPTOR.seams + 1] = selected
   BACKENDS.seams[contract.name] = selected
   for _, effect in ipairs(contract.effects) do
      BACKENDS.byEffect[effect] = "nupp.runtime.backend.browser"
   end
end

local function diagnosticsOf(diagnostics)
   local out = json.asArray({})
   for index, diagnostic in ipairs(diagnostics) do
      out[index] = {
         code = diagnostic.code,
         msg = diagnostic.msg,
         severity = diagnostic.severity,
         line = diagnostic.line,
         col = diagnostic.col,
         offset = diagnostic.offset,
         length = diagnostic.length,
         help = diagnostic.help,
         notes = diagnostic.notes,
         related = diagnostic.related,
      }
   end
   return out
end

local source = "local answer: integer = 42\nreturn answer"
local filename = "differential.nupp"
local parsed = parser.parse(source, filename)
assert(#parsed.errors == 0)

local capabilityResolution = capabilities.resolve("lua51", BACKENDS)
local diagnostics = check.check(parsed, filename, envMod.new(".", {
   cache = false,
   memoryOnly = true,
   dialect = "lua51",
   backendResolution = BACKENDS,
   capabilityResolution = capabilityResolution,
   nativeCompilerServices = false,
   config = {_target = {dialect = "lua51", layoutTarget = "x86_64-unknown-linux-gnu"}},
   typeRoots = {},
   -- No `preludeImage`, unlike `nupp.compiler.browser`'s own session: the image
   -- this process would look for lives beside the playground bundle, not beside
   -- this script's own `require("nupp.compiler.*")` tree, and hydrating one is
   -- a cached shortcut to the same graph a fresh derivation reaches -- not a
   -- second source of truth the generated code could differ over.
}), {
   strict = true,
   dialect = "lua51",
   backendResolution = BACKENDS,
   _capabilityResolution = capabilityResolution,
})
assert(#diagnostics == 0)

optimize.run(parsed, {
   level = 1,
   filename = filename,
   disabled = {},
   dialect = "lua51",
})
parsed.effects = optimize.liveEffects(parsed)
-- The portable bundle both generates for `lua51` and validates the result
-- parses under `lua51` -- see `Session:compile` in `nupp.compiler.browser`.
-- Naming `luajit` here instead would ask for a differential oracle whose
-- generated code this session never actually produces.
local code, generated = gen.generate(parsed, filename, nil, nil, BACKENDS, "lua51")
assert(#generated == 0)

local token = assert(tree.tokenAt(parsed, 7))
local definition = token.definition
local valueType = token.inferredType
if (valueType == nil or valueType == T.any) and definition and definition.type then
   valueType = definition.type
end
assert(valueType)
local name = definition and definition.name or token.text
local prefix = definition and definition.cdef and "cdef " or
   definition and definition.constant and "const " or ""

io.write(json.encode({
   check = {diagnostics = diagnosticsOf(diagnostics)},
   compile = {code = code, diagnostics = diagnosticsOf(diagnostics)},
   hover = {
      found = true,
      name = name,
      signature = prefix .. name .. ": " .. T.tostring(valueType),
      offset = token.offset,
      length = #token.text,
   },
}), "\n")
