-- Acceptance workloads for the closed derive result model. These are deliberately
-- larger than unit recipes: compiler configuration, manifest-cache
-- JSON corpora, and the external Tecs MCP request shape.

local parser = require("nupp.compiler.parser")
local gen = require("nupp.compiler.gen")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function run(source)
   local parsed = parser.parse(source, "derive_acceptance.g.nupp")
   assert(#parsed.errors == 0, "acceptance fixture parses")
   local diagnostics = check.check(parsed, "derive_acceptance.g.nupp", env)
   for _, diagnostic in ipairs(diagnostics) do
      if diagnostic.severity ~= "warning" and diagnostic.severity ~= "note" then
         error(diagnostic.code .. ": " .. diagnostic.msg, 2)
      end
   end
   local code, generated = gen.generate(parsed, "derive_acceptance")
   assert(#generated == 0, generated[1] and generated[1].msg)
   local chunk, why = loadstring(code, "@derive_acceptance")
   assert(chunk, why)
   return chunk(), code
end

local M = {}

function M.replacesCompilerConfigurationAndNewtypeBoilerplate()
   local result = run([[
@derive(nupp.derive.Debug, nupp.derive.Default)
local record PlannerLimits
    @default(2048)
    fields: integer
    @default(16384)
    semanticNodes: integer
    @default(1048576)
    canonicalBytes: integer
    @default(2097152)
    renderedBytes: integer
end

local derived = PlannerLimits.default()
local written = new PlannerLimits(
    fields = 2048,
    semanticNodes = 16384,
    canonicalBytes = 1048576,
    renderedBytes = 2097152
)
return {
    defaultsEqual = derived.fields == written.fields
        and derived.semanticNodes == written.semanticNodes
        and derived.canonicalBytes == written.canonicalBytes
        and derived.renderedBytes == written.renderedBytes,
    debugEqual = derived:debug() == written:debug(),
}
]])
   assert(result.defaultsEqual and result.debugEqual,
      "derived compiler limits differ from the handwritten baseline")
end

function M.matchesManifestAndBuildCacheJSONCorpora()
   local result = run([[
@derive(nupp.derive.JSON)
@json(unknown = "reject")
local record ModuleCache
    sourceHash: string
    interfaceHash: string
    dependencies: {string}
    effects: {string}
    @default(false)
    external: boolean
end

local corpora = {
    new ModuleCache(
        sourceHash = "source-a",
        interfaceHash = "interface-a",
        dependencies = {"nupp.compiler.types", "nupp.compiler.env"},
        effects = {"stdlib.derives"},
        external = false
    ),
    new ModuleCache(
        sourceHash = "source-b",
        interfaceHash = "interface-b",
        dependencies = {},
        effects = {"native.cjson", "stdlib.derives"},
        external = true
    ),
}
local bytes = {}
local accepted = true
for index, value in ipairs(corpora) do
    bytes[index] = value:toJSON()
    local decoded, why = ModuleCache.fromJSON(bytes[index])
    accepted = accepted and decoded ~= nil and why == nil
        and (decoded as ModuleCache).sourceHash == value.sourceHash
        and (decoded as ModuleCache).interfaceHash == value.interfaceHash
end
local rejected, failure = ModuleCache.fromJSON(
    '{"sourceHash":"x","interfaceHash":"y","dependencies":[],"effects":[],"extra":1}'
)
return {bytes = bytes, accepted = accepted, rejected = rejected, failure = failure}
]])
   assert(result.accepted, "the build-cache corpus did not round-trip")
   assert(result.bytes[1] == '{"sourceHash":"source-a","interfaceHash":"interface-a",'
      .. '"dependencies":["nupp.compiler.types","nupp.compiler.env"],'
      .. '"effects":["stdlib.derives"],"external":false}',
      "derived manifest bytes differ from the pinned ordering")
   assert(result.bytes[2] == '{"sourceHash":"source-b","interfaceHash":"interface-b",'
      .. '"dependencies":[],"effects":["native.cjson","stdlib.derives"],'
      .. '"external":true}',
      "derived cache bytes differ from the pinned ordering")
   assert(result.rejected == nil and result.failure:find("unknown field", 1, true),
      "strict manifest validation accepted an unknown key")
end

function M.runsTheExternalTecsMCPRequestCorpus()
   local result = run([[
-- Proving case adapted from tecs.io.mcp.transport.Request. Its private loader.CPtr
-- handle is intentionally outside JSON; the constrained result model refuses it.
@derive(nupp.derive.Debug, nupp.derive.JSON)
@json(unknown = "reject")
local record TecsMCPRequest
    name: string
    arguments: string
end

local corpus = {
    new TecsMCPRequest(name = "world.list", arguments = "{}"),
    new TecsMCPRequest(
        name = "world.spawn",
        arguments = '{"components":["Position","Velocity"]}'
    ),
    new TecsMCPRequest(
        name = "session.inspect",
        arguments = '{"entity":42,"fields":["name"]}'
    ),
}
local bytes, debugged = {}, {}
local accepted = true
for index, request in ipairs(corpus) do
    bytes[index] = request:toJSON()
    debugged[index] = request:debug()
    local decoded, why = TecsMCPRequest.fromJSON(bytes[index])
    accepted = accepted and decoded ~= nil and why == nil
        and (decoded as TecsMCPRequest).name == request.name
        and (decoded as TecsMCPRequest).arguments == request.arguments
end
local malformed, failure = TecsMCPRequest.fromJSON(
    '{"name":"world.list","arguments":"{}","_handle":1}'
)
return {
    bytes = bytes,
    debugged = debugged,
    accepted = accepted,
    malformed = malformed,
    failure = failure,
}
]])
   assert(result.accepted, "the Tecs request corpus did not round-trip")
   assert(result.bytes[1] == '{"name":"world.list","arguments":"{}"}',
      "Tecs request bytes are not deterministic")
   assert(result.debugged[1] ==
      'TecsMCPRequest { name = "world.list", arguments = "{}" }',
      "Tecs request debug output changed")
   assert(result.malformed == nil and result.failure:find("_handle", 1, true),
      "the proving case silently admitted Tecs's private pointer field")
end

return M
