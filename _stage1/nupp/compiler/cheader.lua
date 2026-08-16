_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);














local T = require ( "nupp.compiler.types" )
local cdecl = require ( "nupp.compiler.cdecl" )
local fs = require ( "nupp.compiler.fs" )
local hash = require ( "nupp.compiler.build.hash" )
local process = require ( "nupp.compiler.build.process" )
local buildSyntax = require ( "nupp.compiler.build.syntax" )

local cheader = { }































local INT_BY_BITS = {
[ 8 ] = { T . int8 , T . uint8 } ,
[ 16 ] = { T . int16 , T . uint16 } ,
[ 32 ] = { T . int32 , T . uint32 } ,
[ 64 ] = { T . int64 , T . uint64 } ,
}

local modelFunction
local adoptStruct


local function nuppType ( model , structs , resolver )
local kind = model and model . kind or "unknown"
if kind == "void" then
return nil
elseif kind == "boolean" then
return T . boolean
elseif kind == "float" then
return model . bits == 32 and T . float or T . number
elseif kind == "integer" then
local pair = INT_BY_BITS [ model . bits ]
if not pair then
return T . number
end
return model . unsigned and pair [ 2 ] or pair [ 1 ]
elseif kind == "pointer" then
local pointee = model . to
local readOnly = model . const
if pointee and pointee . kind == "integer" and pointee . bits == 8 then


return T . optional ( T . cstring )
end



if pointee and pointee . kind == "function" then

return T . optional ( modelFunction ( pointee , structs , resolver ) )
end
if pointee and ( pointee . kind == "struct" or pointee . kind == "union" ) then
local named = structs and structs [ pointee . id ]
if not named and resolver and pointee . name then
named = resolver ( pointee . name )
end
if not named and pointee . name then
named = adoptStruct ( pointee . name , pointee . kind )
end
if named then

if readOnly then
named = T . constOf ( named )
end
return T . optional ( T . ptr ( named ) )
end
end
if readOnly then
return T . optional ( T . constOf ( T . voidptr ) )
end
return T . optional ( T . voidptr )
elseif kind == "struct" or kind == "union" then
local named = structs and structs [ model . id ]
if not named and resolver and model . name then
named = resolver ( model . name )
end
if not named and model . name then
named = adoptStruct ( model . name , kind )
end
if named then
return named
end
return T . voidptr
elseif kind == "enum" then
return T . int32
elseif kind == "array" then
return T . voidptr
end

return T . any
end

modelFunction = function ( fn , structs , resolver )
local params = { }
for _ , param in ipairs ( fn . params or { } ) do
params [ # params + 1 ] = nuppType ( param . type , structs , resolver ) or T . any
end
local rets = { }
local ret = nuppType ( fn . returns , structs , resolver )
if ret then
rets [ 1 ] = ret
end

return T . func (
params ,
rets ,
fn . vararg ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
nil ,
true
)
end



local function stripDirectives ( text )
text = text : gsub ( "/%*.-%*/" , " " )
local out = { }
for line in ( text .. "\n" ) : gmatch ( "(.-)\n" ) do
if not line : match ( "^%s*#" ) then
out [ # out + 1 ] = ( line : gsub ( "//.*$" , "" ) )
end
end

return table . concat ( out , "\n" )
end

local function readFile ( path )
local f = io . open ( path , "rb" )
if not f then
return nil
end
local text = f : read ( "*a" )
f : close ( )

return text
end


local toolchainCache = { }
local function toolchainTag ( opts )
if not opts . preprocess then
return "-"
end
local argv = { opts . cc or "cc" }
for _ , arg in ipairs ( opts . ccArgs or { } ) do
argv [ # argv + 1 ] = arg
end
argv [ # argv + 1 ] = "--version"
local key = table . concat ( argv , "\0" )
local hit = toolchainCache [ key ]
if hit then
return hit
end
local code , output = process . capture ( argv )
local version = code == 0 and output : match ( "[^\r\n]+" ) or "unknown"
toolchainCache [ key ] = version

return version
end

local function toolchainIdentity ( opts )
local parts = { opts . cc or "cc" }
for _ , arg in ipairs ( opts . ccArgs or { } ) do
parts [ # parts + 1 ] = arg
end
parts [ # parts + 1 ] = toolchainTag ( opts )

return table . concat ( parts , "\0" )
end

local function compilerArgv ( opts , ... )
local argv = { opts . cc or "cc" }
for _ , arg in ipairs ( opts . ccArgs or { } ) do
argv [ # argv + 1 ] = arg
end
for _ , arg in ipairs ( { ... } ) do
argv [ # argv + 1 ] = arg
end

return argv
end

local function dependencyPaths ( text , sourcePath )
local paths = buildSyntax . depfile : match ( text ) or { }
if # paths == 0 then
paths [ 1 ] = sourcePath
end
local unique , out = { } , { }
for _ , path in ipairs ( paths ) do
path = fs . canonical ( path )
if not unique [ path ] then
unique [ path ] = true
out [ # out + 1 ] = path
end
end
table . sort ( out )

return out
end

local function preprocessHeader ( path , opts )
local depPath = os . tmpname ( )
local argv = compilerArgv ( opts , "-E" , "-MD" , "-MF" , depPath , "-MT" , "nupp_header" , "-xc" , path )
local code , expanded = process . capture ( argv )
local depText = readFile ( depPath )
os . remove ( depPath )
if code ~= 0 then
return nil , nil , expanded ~= "" and expanded or ( "cannot preprocess " .. path )
end
if not depText then
return nil , nil , "compiler did not report dependencies for " .. path
end
if # expanded == 0 then
return nil , nil , "cc -E produced no output for " .. path
end

return expanded , dependencyPaths ( depText , path )
end

local function semanticText ( text )
text = text : gsub ( "%s+" , " " )
text = text : gsub ( "%s*([{}%(%)%[%],;%*])%s*" , "%1" )
return text : match ( "^%s*(.-)%s*$" ) or text
end

local cache = { }

local function provenance ( path , opts )
opts = opts or { }
path = fs . canonical ( path )
local source = opts . read and opts . read ( path ) or readFile ( path )
if not source then
return nil , "cannot read " .. path
end
local text = source
local dependencies = { path }
if opts . preprocess then
local expanded , discovered , problem = preprocessHeader ( path , opts )
if not expanded then
return nil , problem
end
text = expanded
dependencies = discovered
end
text = stripDirectives ( text )
local semanticFingerprint = hash . digest (
table . concat ( { "cheader-v2" , cdecl . abiTag ( ) , toolchainIdentity ( opts ) , semanticText ( text ) } , "\0" )
)

return { cdef = text , sourcePath = path , dependencies = dependencies , semanticFingerprint = semanticFingerprint , }
end

cheader . provenance = provenance





local declaredBlocks = { }
local declaredNames = { }







function cheader . declare ( text )
if declaredBlocks [ text ] ~= nil then
return declaredBlocks [ text ] , nil , declaredNames [ text ]
end
local ok , err , names = cdecl . declare ( text )
declaredBlocks [ text ] = ok
declaredNames [ text ] = names or { }
if not ok then
return false , err
end

return true , nil , declaredNames [ text ]
end






local adopted = { }
local function adoptingResolver ( resolver )
return function ( tag )
if resolver then
local known = resolver ( tag )
if known then
return known
end
end

return adoptStruct ( tag , "struct" ) or adoptStruct ( tag , "union" )
end
end

adoptStruct = function ( tag , aggregateKind )
aggregateKind = aggregateKind or "struct"
local key = aggregateKind .. " " .. tag
local hit = adopted [ key ]
if hit then
return hit
end
local model = cdecl . typeFromString ( key )
if not model or model . kind ~= aggregateKind then
return nil
end
local declaration = cdecl . structById ( model . id )
if not declaration then
return nil
end
local nominal = T . nominal ( tag , "struct" )
nominal . cdefName = tag
nominal . cdefKind = aggregateKind
nominal . fieldOrder = { }
adopted [ key ] = nominal
for _ , field in ipairs ( declaration . fields ) do
local fieldType = nuppType ( field . type , nil , adoptingResolver ( nil ) ) or T . any
nominal . byname [ field . name ] = fieldType
nominal . writeByname [ field . name ] = fieldType
nominal . fieldOrder [ # nominal . fieldOrder + 1 ] = field . name
end

return nominal
end

function cheader . typeFromString ( spec , resolver )
local model , err = cdecl . typeFromString ( spec )
if not model then
return nil , err
end

return nuppType ( model , nil , adoptingResolver ( resolver ) )
end





function cheader . declaredFunctions ( resolver , only )
local out = { }
local r = adoptingResolver ( resolver )
for name , fn in pairs ( cdecl . declaredFunctions ( only ) ) do
out [ name ] = modelFunction ( fn , nil , r )
end

return out
end




function cheader . load ( path , opts )
opts = opts or { }
local observed , problem = provenance ( path , opts )
if not observed then
return nil , problem
end
local text = observed . cdef
local dependencies = observed . dependencies
local semanticFingerprint = observed . semanticFingerprint


local key = table . concat ( { semanticFingerprint , table . concat ( dependencies , "\0" ) } , "\0" )
local hit = cache [ key ]
if hit then
return {
exports = hit . exports ,
cdef = hit . cdef ,
sourcePath = observed . sourcePath ,
dependencies = dependencies ,
semanticFingerprint = semanticFingerprint ,
}
end

local parsed , err = cdecl . inspect ( text )
if not parsed then
return nil , ( "LuaJIT could not parse %s: %s" ) : format ( path , tostring ( err ) )
end


local structs , exports = { } , { }
for _ , declaration in ipairs ( parsed . structs ) do
local nominal = T . nominal ( declaration . name , "struct" )
nominal . cdefName = declaration . name
nominal . cdefKind = declaration . kind
nominal . fieldOrder = { }
structs [ declaration . id ] = nominal
end
for _ , declaration in ipairs ( parsed . structs ) do
local nominal = structs [ declaration . id ]
for _ , field in ipairs ( declaration . fields ) do
local fieldType = nuppType ( field . type , structs ) or T . any
nominal . byname [ field . name ] = fieldType
nominal . writeByname [ field . name ] = fieldType
nominal . fieldOrder [ # nominal . fieldOrder + 1 ] = field . name
end
end
for _ , fn in ipairs ( parsed . functions ) do
exports [ fn . name ] = modelFunction ( fn , structs )
end

local result = {
exports = exports ,
cdef = text ,
sourcePath = observed . sourcePath ,
dependencies = dependencies ,
semanticFingerprint = semanticFingerprint ,
}
cache [ key ] = result

return result
end

return cheader
