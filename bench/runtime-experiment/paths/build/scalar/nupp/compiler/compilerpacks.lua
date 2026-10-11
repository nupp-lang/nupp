_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()local __nuppT1={ _G.nupp.__reflect.declaration("nupp.compiler.compilerpacks\0runtime\0001") };











const json = require ( "nupp.codec.json" )

local fs = require ( "nupp.compiler.fs" )
local hash = require ( "nupp.compiler.hash" )
local layouts = require ( "nupp.compiler.targetlayout" )
local profiles = require ( "nupp.compiler.targetprofile" )

local packs = { }

packs.Pack = {} packs.Pack.__index = packs.Pack ;_G.nupp.__reflect.link(packs.Pack,__nuppT1[1],{ _G.nupp.__reflect.reference("nupp.compiler.targetprofile\0runtime\0001","nupp.compiler.targetprofile") })
















local function safeRelative ( path ) 
return type ( path ) == "string"
and path ~= ""
and path : sub ( 1 , 1 ) ~= "/"
and path : sub ( 1 , 1 ) ~= "\\"
and not path : find ( "\\" , 1 , true )
and not path : find ( ".." , 1 , true )
end

local function readTool ( root , value , label ) 
if type ( value ) ~= "table" or not safeRelative ( value . path ) then
return nil , label .. " requires a safe relative path"
end
if type ( value . sha256 ) ~= "string" or # value . sha256 ~= 64 or not value . sha256 : match ( "^[0-9a-f][0-9a-f]+$" ) then
return nil , label .. " requires a lowercase SHA-256"
end
if type ( value . size ) ~= "number" or value . size < 1 or value . size ~= math . floor ( value . size ) then
return nil , label .. " requires a positive integer size"
end
local path = fs . join ( root , value . path )
local bytes , readErr = fs . readFile ( path )
if not bytes then
return nil , "cannot read " .. label .. " " .. path .. ": " .. tostring ( readErr )
end
if # bytes ~= value . size then
return nil , ("%s %s has %d bytes, expected %d") : format ( label , path , # bytes , value . size )
end
local digest = hash . sha256 ( bytes )
if digest ~= value . sha256 then
return nil , label .. " " .. path .. " has SHA-256 " .. digest .. ", expected " .. value . sha256
end

return path , nil
end

local function stringArray ( value , label ) 
if value == nil then
return { } , nil
end
if type ( value ) ~= "table" then
return nil , label .. " must be an array of strings"
end
local out = { }
for index , item in ipairs ( value ) do
if type ( item ) ~= "string" then
return nil , label .. "[" .. index .. "] must be a string"
end
out [ # out + 1 ] = item
end
if # out ~= # value then
return nil , label .. " must not have gaps"
end

return out , nil
end

local function packFlags ( flags , root ) 
local expanded = { }

local function packRoot ( ) 
return root
end

for _ , flag in ipairs ( flags ) do
expanded [ # expanded + 1 ] = flag : gsub ( "{pack}" , packRoot )
end

return expanded
end



function packs . resolve ( target ) 
local directory = os . getenv ( "NUPP_COMPILER_PACK_DIR" )
local explicit = directory ~= nil and directory ~= ""
local host = layouts . hostKey ( )
if host == nil or target == nil then
return nil , "compiler pack selection needs modeled host and target triples"
end
local directories = { }
if not explicit then



local hosted = rawget ( _G , "__NUPP_EXECUTABLE" )
local executable = type ( hosted ) == "string" and hosted or tostring ( arg and arg [ 0 ] or "" )
local bin = executable : match ( "^(.*)[/\\][^/\\]+$" )
if bin == nil then
return nil , nil
end



directories [ # directories + 1 ] = fs . normalize ( fs . join ( bin , "../lib/nupp/compiler-packs" ) )
directories [ # directories + 1 ] = fs . normalize ( fs . join ( bin , "lib/nupp/compiler-packs" ) )
else
directories [ 1 ] = directory
end
local root , manifestPath , text = nil , nil , nil
for _ , candidate in ipairs ( directories ) do
local candidateRoot = fs . join ( candidate , fs . join ( host , target ) )
local candidateManifest = fs . join ( candidateRoot , "pack.json" )
local candidateText = fs . readFile ( candidateManifest )
if candidateText ~= nil then
root , manifestPath , text = candidateRoot , candidateManifest , candidateText
do break end
end
end
if text == nil then
if not explicit then
return nil , nil
end
return nil , "no compiler pack for " .. host .. " -> " .. target .. " under " .. tostring ( directories [ 1 ] )
end
local selectedRoot = root
local selectedManifest = manifestPath
local value , invalid = json . decode ( text , json . NULL )
if type ( value ) ~= "table" then
return nil , "cannot decode compiler pack " .. selectedManifest .. ": " .. tostring ( invalid or value )
end
if value . schemaVersion ~= 1 or value . host ~= host or value . target ~= target then
return nil , "compiler pack " .. selectedManifest .. " does not describe " .. host .. " -> " .. target
end
if type ( value . version ) ~= "string" or value . version == "" then
return nil , "compiler pack " .. selectedManifest .. " requires a version"
end
local cc , ccErr = readTool ( selectedRoot , value . cc , "compiler pack cc" )
if not cc then
return nil , ccErr
end
local ar , arErr = readTool ( selectedRoot , value . ar , "compiler pack ar" )
if not ar then
return nil , arErr
end
local compileFlags , compileErr = stringArray ( value . compileFlags , "compiler pack compileFlags" )
if not compileFlags then
return nil , compileErr
end
local linkFlags , flagsErr = stringArray ( value . linkFlags , "compiler pack linkFlags" )
if not linkFlags then
return nil , flagsErr
end
local profile = nil
if value . profile ~= nil then
local described , profileErr = profiles . fromDescriptor ( target , value . profile , selectedManifest )
if described == nil then
return nil , profileErr
end
profile = described
end

return _G.setmetatable({ host =
host ,  target =
target ,  version =
value . version ,  manifestDigest =
hash . digest ( text ) ,  cc =
cc ,  ar =
ar ,  compileFlags =
packFlags ( compileFlags , selectedRoot ) ,  linkFlags =
packFlags ( linkFlags , selectedRoot ) ,  profile =
profile }, packs.Pack)
, nil
end






function packs . profile ( target ) 
if target == nil then
return nil , "a target profile needs a target triple"
end
local pack , packErr = packs . resolve ( target )
if pack ~= nil and ( pack ) . profile ~= nil then
return ( pack ) . profile , nil
end
local described , describeErr = profiles . resolve ( target , nil , nil )
if described ~= nil then
return described , nil
end



return nil , packErr or describeErr
end

local __nuppExportValue= packs ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.compilerpacks"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.compilerpacks"]=__nuppExports;return __nuppExports