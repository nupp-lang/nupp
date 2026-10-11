_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local surface = { }

local function facility ( kind , effect ) 
return { kind = kind , effect = effect }
end

local MODULES




= {
[ "bit" ] = ( { kind = "runtime" , effect = "runtime.bitops" } ) ,
[ "nupp.text" ] = ( { kind = "runtime" , effect = "runtime.text_buffer" } ) ,
[ "nupp.codec.json.provider" ] = ( { kind = "runtime" , effect = "native.json" } ) ,
[ "nupp" ] = { kind = "common" } ,
[ "nupp.test" ] = { kind = "common" } ,
[ "nupp.system" ] = ( { kind = "host" , effect = "runtime.system" } ) ,
[ "nupp.spi" ] = { kind = "common" } ,
[ "nupp.codec.hex" ] = { kind = "common" } ,
[ "nupp.digest" ] = ( { kind = "runtime" , effect = "runtime.bitops" } ) ,
[ "nupp.mac.spi" ] = { kind = "common" } ,
[ "nupp.system.spi" ] = { kind = "common" } ,
[ "nupp.host" ] = ( { kind = "host" , effect = "runtime.host" } ) ,
[ "nupp.host.spi" ] = { kind = "common" } ,
[ "nupp.host.pump" ] = { kind = "common" } ,
[ "nupp.host.internal.values" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.runtime.provider.nativehost" ] = ( { kind = "runtime" , effect = "native.host" } ) ,
[ "nupp.runtime.browser.host" ] = ( { kind = "runtime" , effect = "runtime.host" } ) ,
[ "nupp.runtime.browser.hostwire" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.digest.spi" ] = { kind = "common" } ,
[ "nupp.digest.internal.context" ] = { kind = "common" } ,
[ "nupp.digest.internal.builtin" ] = ( { kind = "runtime" , effect = "runtime.bitops" } ) ,
[ "nupp.digest.internal.words" ] = ( { kind = "runtime" , effect = "runtime.bitops" } ) ,
[ "nupp.digest.internal.constants" ] = { kind = "common" } ,
[ "nupp.checksum" ] = { kind = "common" } ,
[ "nupp.checksum.spi" ] = { kind = "common" } ,
[ "nupp.checksum.internal.builtin" ] = { kind = "common" } ,
[ "nupp.runtime.provider.nativecrc" ] = ( { kind = "runtime" , effect = "native.crc" } ) ,
[ "nupp.mac" ] = ( { kind = "runtime" , effect = "runtime.bitops" } ) ,
[ "nupp.compression" ] = ( { kind = "runtime" , effect = "runtime.compression" } ) ,
[ "nupp.compression.spi" ] = { kind = "common" } ,
[ "nupp.runtime.provider.nativecompression" ] = ( { kind = "runtime" , effect = "native.compression" } ) ,
[ "nupp.util.internal.hash" ] = ( { kind = "runtime" , effect = "runtime.bitops" } ) ,
[ "nupp.util.internal.uuid" ] = ( { kind = "runtime" , effect = "runtime.uuid" } ) ,
[ "nupp.util" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.util.internal.bitset" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.util.internal.store" ] = { kind = "common" } ,
[ "nupp.util.internal.protected" ] = { kind = "common" } ,
[ "nupp.codec.json" ] = ( { kind = "runtime" , effect = "native.json" } ) ,
[ "nupp.serde" ] = { kind = "common" } ,
[ "nupp.serde.internal.accessors" ] = { kind = "common" } ,
[ "nupp.serde.internal.context" ] = { kind = "common" } ,
[ "nupp.serde.debug" ] = { kind = "common" } ,
[ "nupp.serde.internal.declaration" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.defaults" ] = { kind = "common" } ,
[ "nupp.serde.internal.document" ] = { kind = "common" } ,
[ "nupp.serde.internal.documentcodec" ] = { kind = "common" } ,
[ "nupp.serde.internal.documentreader" ] = { kind = "common" } ,
[ "nupp.serde.internal.documentwriter" ] = { kind = "common" } ,
[ "nupp.serde.internal.errors" ] = { kind = "common" } ,
[ "nupp.serde.adapters" ] = { kind = "common" } ,
[ "nupp.serde.codec" ] = { kind = "common" } ,
[ "nupp.serde.internal.identity" ] = { kind = "common" } ,
[ "nupp.serde.document" ] = { kind = "common" } ,
[ "nupp.serde.json" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.compiled" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.encoder" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.diagnostic" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.document" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.extensions" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.lower" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.plan" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.reader" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.syntax" ] = { kind = "common" } ,
[ "nupp.serde.internal.json.writer" ] = { kind = "common" } ,
[ "nupp.serde.internal.list" ] = { kind = "common" } ,
[ "nupp.serde.internal.memo" ] = { kind = "common" } ,
[ "nupp.serde.internal.indexed" ] = { kind = "common" } ,
[ "nupp.serde.native" ] = { kind = "common" } ,
[ "nupp.serde.internal.native.reader" ] = { kind = "common" } ,
[ "nupp.serde.internal.native.writer" ] = { kind = "common" } ,
[ "nupp.serde.internal.numbers" ] = { kind = "common" } ,
[ "nupp.serde.internal.persistence" ] = { kind = "common" } ,
[ "nupp.serde.internal.publication" ] = { kind = "common" } ,
[ "nupp.serde.internal.scalar" ] = { kind = "common" } ,
[ "nupp.serde.internal.structure" ] = { kind = "common" } ,
[ "nupp.serde.internal.timestamps" ] = { kind = "common" } ,
[ "nupp.serde.internal.value" ] = { kind = "common" } ,
[ "nupp.serde.internal.view" ] = { kind = "common" } ,
[ "nupp.text.utf8" ] = { kind = "common" } ,
[ "nupp.derive" ] = ( { kind = "runtime" , effect = "runtime.text_buffer" } ) ,
[ "nupp.cli" ] = { kind = "common" } ,
[ "nupp.cli.internal.optparser" ] = { kind = "common" } ,
[ "nupp.cli.internal.decode" ] = { kind = "common" } ,
[ "nupp.cli.internal.terminal" ] = { kind = "common" } ,
[ "nupp.cli.internal.application" ] = { kind = "common" } ,
[ "nupp.gpu" ] = ( { kind = "runtime" , effect = "runtime.gpu" } ) ,
[ "nupp.gpu.internal" ] = { kind = "common" } ,
[ "nupp.digest.internal.streaming" ] = ( { kind = "runtime" , effect = "runtime.bitops" } ) ,
[ "nupp.gpu.layoutfacts" ] = { kind = "common" } ,
[ "nupp.gpu.layout" ] = { kind = "common" } ,
[ "nupp.runtime.hotreload" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.runtime.storage" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.io" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.io.internal.bytes" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.io.internal.ownedreader" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.io.internal.scalars" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.io.internal.lines" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.io.http.internal.transport" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.io.path.provider" ] = ( { kind = "host" , effect = "runtime.path_provider" } ) ,
[ "nupp.io.path.pathtext" ] = { kind = "common" } ,
[ "nupp.io.files" ] = ( { kind = "host" , effect = "runtime.files" } ) ,
[ "nupp.io.files.messages" ] = { kind = "common" } ,
[ "nupp.io.files.path" ] = { kind = "common" } ,
[ "nupp.io.files.spi" ] = { kind = "common" } ,
[ "nupp.runtime.provider.nativefiles" ] = ( { kind = "runtime" , effect = "native.files" } ) ,
[ "nupp.runtime.browser.files" ] = ( { kind = "runtime" , effect = "runtime.files" } ) ,
[ "nupp.io.http" ] = ( { kind = "host" , effect = "runtime.http" } ) ,
[ "nupp.io.path" ] = { kind = "common" } ,
[ "nupp.codec.base64" ] = { kind = "common" } ,
[ "nupp.codec.valuebuilder" ] = { kind = "common" } ,
[ "nupp.io.net" ] = ( { kind = "host" , effect = "runtime.net" } ) ,
[ "nupp.io.process" ] = ( { kind = "host" , effect = "runtime.process" } ) ,
[ "nupp.io.tls" ] = ( { kind = "host" , effect = "runtime.tls" } ) ,
[ "nupp.io.uri" ] = ( { kind = "runtime" , effect = "runtime.uri_provider" } ) ,
[ "nupp.io.uri.provider" ] = ( { kind = "runtime" , effect = "runtime.uri_provider" } ) ,
[ "nupp.log" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.compiler.runtime.extensions" ] = { kind = "compiler" } ,
[ "nupp.compiler.runtime.math" ] = { kind = "compiler" } ,
[ "nupp.compiler.runtime.peg" ] = ( { kind = "runtime" , effect = "native.lpeg" } ) ,
[ "nupp.compiler.runtime.reflect" ] = { kind = "compiler" } ,
[ "nupp.mem" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.mem.heap" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.mem.indexed" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.mem.sharedbytes" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.mem.soa" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.mem.span" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.runtime.native" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.profile" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.profile.trace" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.profile.zone" ] = { kind = "unavailable" , capability = "cinterop" } ,


[ "nupp.bench" ] = { kind = "unavailable" , capability = "cinterop" } ,
[ "nupp.random" ] = ( { kind = "host" , effect = "runtime.crypto" } ) ,
[ "nupp.simd" ] = { kind = "common" } ,
[ "nupp.suspension" ] = { kind = "common" } ,
[ "nupp.suspension.host" ] = { kind = "common" } ,
[ "nupp.suspension.selected" ] = { kind = "common" } ,
[ "nupp.tasks" ] = { kind = "common" } ,
[ "nupp.time" ] = ( { kind = "host" , effect = "runtime.time" } ) ,
[ "nupp.workers" ] = ( { kind = "host" , effect = "runtime.workers" } ) ,
[ "nupp.mem.array" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.util.internal.pool" ] = { kind = "common" } ,
[ "nupp.mem.arena" ] = { kind = "unavailable" , capability = "cstorage" } ,
[ "nupp.events" ] = { kind = "unavailable" , capability = "cstorage" } ,
}

local BROWSER_IMPLEMENTATIONS = {
[ "nupp.runtime.browser.crc" ] = true ,
[ "nupp.runtime.browser.system" ] = true ,
[ "nupp.runtime.browser.host" ] = true ,
[ "nupp.runtime.browser.webgpu.internal" ] = true ,
[ "nupp.runtime.browser.http" ] = true ,
[ "nupp.runtime.browser.files" ] = true ,
[ "nupp.runtime.browser.workers" ] = true ,
[ "nupp.runtime.browser.crypto" ] = true ,
[ "nupp.runtime.browser.suspension" ] = true ,
[ "nupp.runtime.browser.uri" ] = true ,
[ "nupp.runtime.browser.path" ] = true ,
[ "nupp.runtime.browser.time" ] = true ,
}


function surface . supports ( moduleName , host ) 
local selectedHost = host or "native"
if BROWSER_IMPLEMENTATIONS [ moduleName ] then
return selectedHost == "browser"
end
if moduleName == "nupp.runtime.provider.nativebuffer"
or moduleName == "nupp.runtime.provider.nativestorage"
or moduleName == "bit"
then
return true
end
if selectedHost == "browser" then
local native = require ( "nupp.compiler.native" )
for _ , effect in ipairs ( native . effectNames ( ) ) do
local feature = native . feature ( effect )
if feature . runtimeModule == moduleName and not feature . portableRuntime then
return false
end
end
end
if moduleName : match ( "^nupp%.runtime%.provider%.native" )
or moduleName == "nupp.runtime.provider.workers"
or moduleName == "nupp.runtime.provider.suspension"
or moduleName == "nupp.codec.json.aot"
then
return selectedHost == "native"
end

return true
end

function surface . classify ( moduleName ) 
return MODULES [ moduleName ]
end

function surface . all ( ) 
local copy = { }
for name , classification in pairs ( MODULES ) do
copy [ name ] = classification
end

return copy
end


function surface . compatible ( moduleName ) 
local classification = MODULES [ moduleName ]
if classification and classification . kind == "unavailable" then
return false
end
local native = require ( "nupp.compiler.native" )
for _ , effect in ipairs ( native . effectNames ( ) ) do
local feature = native . feature ( effect )
if feature . runtimeModule == moduleName and not feature . portableRuntime then
return false
end
end

return true
end

local function reach ( checker , moduleName , at ) 
if not surface . supports ( moduleName , checker . env and checker . env . artifactHost ) then
if at ~= nil then
checker . diag (
"NUPP3006" ,
at ,
("module %q is not available on host %q")

: format ( moduleName , checker . env and checker . env . artifactHost or "native" )
)
end
return false
end

return true
end

function surface . reachable ( checker , moduleName ) 
return reach ( checker , moduleName , nil )
end

function surface . accelerators ( moduleName ) 
local classification = MODULES [ moduleName ]

return classification and classification . accelerators or nil
end

function surface . requireModule ( checker , moduleName , at ) 
if not reach ( checker , moduleName , at ) then
return nil
end
return nil
end

function surface . requireMember ( checker , moduleName , member , at ) 
return nil
end

local __nuppExportValue= surface ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.standardsurface"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.standardsurface"]=__nuppExports;return __nuppExports