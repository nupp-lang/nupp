_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);







local native = { }


















local FEATURES = {
[ "native.lpeg" ] = { name = "lpeg" , module = "lpeg" , host = "lpeg" , binary = true , } ,
[ "stdlib.lpeg.re" ] = { name = "lpeg_re" , module = "re" , requires = { "native.lpeg" } , } ,
[
"native.cjson"
] = {
name = "cjson" ,
globals = { "nupp.data.json" } ,
modules = { "cjson" , "cjson.safe" } ,
host = "cjson" ,
binary = true ,
} ,
[
"native.lua_utf8"
] = { name = "lua_utf8" , globals = { "nupp.data.utf8" } , module = "lua-utf8" , host = "lua-utf8" , binary = true , } ,
[ "stdlib.peg" ] = { name = "peg" , requires = { "native.lpeg" } , } ,
[ "stdlib.peg.compile" ] = { name = "peg_compile" , globals = { "nupp.peg.compile" } , requires = { "native.lpeg" } , } ,
[ "stdlib.fieldcodec" ] = { name = "fieldcodec" , globals = { "nupp.reflect.fieldCodec" } , } ,
[ "stdlib.derives" ] = { name = "derives" , globals = { } , } ,
[ "stdlib.io" ] = { name = "io" , globals = { "nupp.io.newBuffer" , "nupp.io.newStringReader" } , } ,
[ "stdlib.math" ] = { name = "math" , globals = { "nupp.math" } , } ,
[ "stdlib.bitset" ] = {
name = "bitset" ,
globals = { "nupp.data.bitset" } ,


} ,
[
"stdlib.log"
] = {
name = "log" ,
globals = {
"nupp.log.error" ,
"nupp.log.warn" ,
"nupp.log.info" ,
"nupp.log.debug" ,
"nupp.log.level" ,
"nupp.log.enabled" ,
"nupp.log.sink" ,
"nupp.log.formatter" ,
"nupp.log.timestamp" ,
"nupp.log.timestampFormat" ,
"nupp.log.named" ,
"nupp.log.levelName" ,
} ,
} ,
[ "stdlib.fnv1a64" ] = { name = "fnv1a64" , globals = { "nupp.data.fnv1a64" } , } ,
[ "stdlib.checksums" ] = { name = "checksums" , globals = { "nupp.data.crc32" } , } ,
[
"native.path"
] = {
name = "path" ,
globals = { "nupp.io.Path.new" , "nupp.io.Path.currentDirectory" , "nupp.io.Path.separator" } ,
cargo = "runtime/native/Cargo.toml" ,
cargoFeature = "path" ,
library = "nupp_native" ,
binary = true ,
} ,
[
"native.uri"
] = {
name = "uri" ,
globals = { "nupp.io.URI.new" , "nupp.io.URI.validate" , "nupp.io.URI.isURI" } ,
cargo = "runtime/native/Cargo.toml" ,
cargoFeature = "uri" ,
library = "nupp_native" ,
binary = true ,
} ,
[
"native.uuid"
] = {
name = "uuid" ,
globals = { "nupp.data.uuid4" , "nupp.data.uuid7" } ,
cargo = "runtime/native/Cargo.toml" ,
cargoFeature = "uuid" ,
library = "nupp_native" ,
binary = true ,
} ,
[ "native.files" ] = {
name = "files" ,
globals = { "nupp.io.files" } ,
cargo = "runtime/native/Cargo.toml" ,
cargoFeature = "files" ,
host = "native-files" ,
library = "nupp_native" ,
binary = true ,


requires = { "runtime.suspension" } ,
} ,
[ "runtime.suspension" ] = {



name = "suspension" ,
runtimeModule = "nupp.suspension" ,
} ,
[ "native.process" ] = {
name = "process" ,





module = "nupp.io.process" ,
runtimeModule = "nupp.io.process" ,
cargo = "runtime/native/Cargo.toml" ,
cargoFeature = "process" ,
host = "native-process" ,
library = "nupp_native" ,
binary = true ,
requires = { "runtime.suspension" } ,
} ,
[
"native.workers"
] = {
name = "workers" ,
module = "nupp.workers" ,
host = "workers" ,
binary = true ,
runtimeModule = "nupp.workers" ,
requires = { "runtime.suspension" } ,
} ,
[
"native.http"
] = {
name = "http" ,
module = "nupp.io.http" ,
runtimeModule = "nupp.io.http" ,
cargo = "runtime/native/Cargo.toml" ,
cargoFeature = "http" ,
library = "nupp_native" ,
binary = true ,
requires = { "runtime.suspension" , "native.uri" , "stdlib.io" } ,
} ,
[
"native.sha256"
] = {
name = "sha256" ,
globals = { "nupp.data.sha256" } ,
cargo = "runtime/native/Cargo.toml" ,
cargoFeature = "sha256" ,
library = "nupp_native" ,
binary = true ,
} ,
}

local byGlobal , byModule , byName = { } , { } , { }
for effect , feature in pairs ( FEATURES ) do
if feature . binary then
byName [ feature . name ] = effect
end
for _ , path in ipairs ( feature . globals or { } ) do
byGlobal [ path ] = effect
end
if feature . module then
byModule [ feature . module ] = effect
end
for _ , moduleName in ipairs ( feature . modules or { } ) do
byModule [ moduleName ] = effect
end
end

function native . forGlobal ( path )
return byGlobal [ path ]
end




function native . decorateGlobals ( globals )
local effects = { }
local function decorate ( owner , member , effect )
if owner then
effects [ owner ] = effects [ owner ] or { }
effects [ owner ] [ member ] = effect
end
end

for path , effect in pairs ( byGlobal ) do
local parts = { }
for part in path : gmatch ( "[^.]+" ) do
parts [ # parts + 1 ] = part
end
local entry = globals [ parts [ 1 ] ]
local t = entry and entry . t
for index = 2 , # parts do
if index == # parts and t then
decorate ( t , parts [ index ] , effect )





local qualified = globals [ table . concat ( parts , "." , 1 , index - 1 ) ]
decorate ( qualified and qualified . t , parts [ index ] , effect )
end




t = t and ( t . byname and t . byname [ parts [ index ] ] or t . nestedTypes and t . nestedTypes [ parts [ index ] ] ) or nil
end
end

return effects
end

function native . forModule ( name )
return byModule [ name ]
end

function native . feature ( effect )
return FEATURES [ effect ]
end

function native . featureNames ( )
local names = { }
for name in pairs ( byName ) do
names [ # names + 1 ] = name
end
table . sort ( names )

return names
end







function native . expand ( effects )
local closed = { }
local pending = { }
for effect in pairs ( effects or { } ) do
closed [ effect ] = true
pending [ # pending + 1 ] = effect
end
while # pending > 0 do
local effect = table . remove ( pending )
local feature = FEATURES [ effect ]
for _ , needed in ipairs ( feature and feature . requires or { } ) do
if not closed [ needed ] then
closed [ needed ] = true
pending [ # pending + 1 ] = needed
end
end
end

return closed
end






function native . resolve ( effects , overrides )
local resolved = { }
for effect in pairs ( effects or { } ) do
resolved [ effect ] = true
end
for name , enabled in pairs ( overrides or { } ) do
local effect = byName [ name ]
if effect then
resolved [ effect ] = enabled and true or nil
end
end

return native . expand ( resolved )
end




function native . sourceEffects ( source , filename , env )
local parser = require ( "nupp.compiler.parser" )
local parsed = parser . parse ( source , filename )
if # parsed . errors > 0 then
return { }
end
local checker = require ( "nupp.compiler.check" )
checker . check ( parsed , filename , env , { strict = false } )

return parsed . effects or { }
end

function native . features ( effects )
local out = { }
for effect in pairs ( effects or { } ) do
local feature = FEATURES [ effect ]
if feature then
out [ # out + 1 ] = feature
end
end
table . sort ( out , function ( a , b )
return a . name < b . name
end )

return out
end

return native
