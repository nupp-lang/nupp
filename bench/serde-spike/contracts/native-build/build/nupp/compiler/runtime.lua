_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()












local envMod = require ( "nupp.compiler.project.env" )

local runtime = { }





function runtime . install (
env ,
compile ,
loaded ,
checkPlain ,
preparing
) 
local loaders = package . loaders
assert ( loaders , "this Lua runtime does not expose package loaders" )
assert ( type ( compile ) == "function" , "compile callback must be a function" )

local function pack ( ... ) 
return { n = select ( "#" , ... ) , ... }
end

local unpackAny = unpack






local compiling = false

local function loadLjppModule ( name ) 
if compiling then
return
end
local path = envMod . findRuntimeModulePath ( env , name )
if not path then
return ("\n\9no nupp source for module '%s'") : format ( name )
end

local chunk , loadErr
if path : match ( "%.nupp$" ) then
compiling = true
local ok , code , compileErr = pcall ( compile , path , env )
compiling = false
if not ok then
error ( code , 0 )
end
if not code then
error (
("error compiling nupp module '%s' from '%s': %s")

: format ( name , path , compileErr or "compilation failed" ) ,
0
)
end
chunk , loadErr = loadstring ( code , "@" .. path )
else





if checkPlain and not checkPlain ( path , env ) then
error ( ("error checking lua module '%s' from '%s': type errors") : format ( name , path ) , 0 )
end
chunk , loadErr = loadfile ( path )
end
if not chunk then
error ( ("error loading project module '%s' from '%s': %s") : format ( name , path , tostring ( loadErr ) ) , 0 )
end

if not loaded or not path : match ( "%.nupp$" ) then
return chunk
end





return function ( ... ) 
local args = { n = select ( "#" , ... ) , ... }
local result
local ok , failure = pcall ( function ( ) 
result = pack ( chunk ( unpackAny ( args , 1 , args . n ) ) )
end )
loaded ( name , path , ok )
if not ok then
error ( failure , 0 )
end

return unpack ( result , 1 , result . n )
end
end



local installedLoader = loadLjppModule
if preparing then
installedLoader = function ( name ) 
preparing ( true )
local ok , result = pcall ( loadLjppModule , name )
preparing ( false )
if not ok then
error ( result , 0 )
end

return result
end
end

table . insert ( loaders , 2 , installedLoader )

local installed = true

return function ( ) 
if not installed then
return
end
installed = false
for j , loader in ipairs ( loaders ) do
if loader == installedLoader then
table . remove ( loaders , j )
return
end
end
end
end

local __nuppExportValue= runtime ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.compiler.runtime"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.compiler.runtime"]=__nuppExports;return __nuppExports