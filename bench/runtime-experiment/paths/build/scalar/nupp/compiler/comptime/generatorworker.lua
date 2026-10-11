_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






local fs = require ( "nupp.compiler.fs" )
local json = require ( "nupp.codec.json" )

local worker = { }

local function contained ( root , path ) 
root = fs . absolute ( root )
path = fs . absolute ( path )
return path == root or path : sub ( 1 , # root + 1 ) == root .. "/"
end

function worker . main ( argv ) 
local requestPath , resultPath = argv [ 1 ] , argv [ 2 ]
local text = requestPath and fs . readFile ( requestPath )
local wire = nil
if text then
wire = json . decode ( text , json . NULL )
end
if type ( wire ) ~= "table" or not resultPath then
return 2
end
package . path = tostring ( wire . path or "" ) .. ";" .. package . path
package . cpath = tostring ( wire . cpath or "" ) .. ";" .. package . cpath

local inputs = { }
for _ , path in ipairs ( wire . inputs or { } ) do
inputs [ fs . canonical ( path ) ] = true
end
local diagnostics = { }
local request = {
name = wire . name ,
inputRoot = wire . inputRoot ,
outputRoot = wire . outputRoot ,
inputs = wire . inputs ,
options = wire . options or { } ,
}
function request . read ( path ) 
local resolved = fs . canonical ( fs . join ( wire . inputRoot , path ) )
if not inputs [ resolved ] then
error ( "generator read is not a declared input: " .. path , 2 )
end
local contents , err = fs . readFile ( resolved )
if not contents then
error ( tostring ( err ) , 2 )
end

return contents
end

function request . write ( path , contents ) 
local resolved = fs . absolute ( fs . join ( wire . outputRoot , path ) )
if not contained ( wire . outputRoot , resolved ) or resolved == fs . absolute ( wire . outputRoot ) then
error ( "generator output must stay inside outputRoot: " .. path , 2 )
end
local wrote , err = fs . writeFile ( resolved , contents )
if not wrote then
error ( tostring ( err ) , 2 )
end
end

function request . diagnostic ( severity , message ) 
diagnostics [ # diagnostics + 1 ] = { severity = severity , message = message }
end

local succeeded , failure = xpcall (
function ( ) 
local provider = require ( wire . entry )
local generate = type ( provider ) == "table" and ( provider ) . generate or provider
if type ( generate ) ~= "function" then
error ( wire . entry .. " must return a function or a table with generate" , 0 )
end
generate ( request )
end ,
function ( problem ) 
return debug . traceback ( tostring ( problem ) )
end
)
fs . writeFile ( resultPath , json . encode ( { ok = succeeded , error = failure , diagnostics = diagnostics } ) .. "\n" )

return succeeded and 0 or 1
end

local __nuppExportValue= worker ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.comptime.generatorworker"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.comptime.generatorworker"]=__nuppExports;return __nuppExports