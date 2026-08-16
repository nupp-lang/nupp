_G.assert(_G.loadstring("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,\"data\")or{};rawset(__nupp,\"data\",__nuppData);local __nuppIO=rawget(__nupp,\"io\")or{};rawset(__nupp,\"io\",__nuppIO);local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath);local __nuppCleanups=_G.__nuppCleanupRegistry;if __nuppCleanups==nil then __nuppCleanups={};_G.__nuppCleanupRegistry=__nuppCleanups end;\n\n\n\n\nlocal function __nuppDestroyByteView ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView\n\nlocal function __nuppDestroyReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader\n\nlocal function __nuppDestroyWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter\n\nlocal function __nuppDestroyBuffer ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer\n\nlocal function __nuppDestroyFile ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile\n\nlocal function __nuppDestroyTemporaryPath ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath\n\nlocal function __nuppDestroyScalarReader ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader\n\nlocal function __nuppDestroyScalarWriter ( value )\ndo\nvalue : drop ( )\nend\nend ;__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter\n\n\n\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyByteView\"]=__nuppDestroyByteView;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyReader\"]=__nuppDestroyReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyWriter\"]=__nuppDestroyWriter;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyBuffer\"]=__nuppDestroyBuffer;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyFile\"]=__nuppDestroyFile;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyTemporaryPath\"]=__nuppDestroyTemporaryPath;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarReader\"]=__nuppDestroyScalarReader;\n__nuppCleanups[\"nupp:prelude.d.nupp#__nuppDestroyScalarWriter\"]=__nuppDestroyScalarWriter;\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppData=rawget(__nupp,"data")or{};rawset(__nupp,"data",__nuppData);local __nuppIO=rawget(__nupp,"io")or{};rawset(__nupp,"io",__nuppIO);local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath);










local envMod = require ( "nupp.compiler.env" )

local runtime = { }





function runtime . install (
env ,
compile ,
loaded
)
local loaders = package . loaders
assert ( loaders , "this Lua runtime does not expose package loaders" )
assert ( type ( compile ) == "function" , "compile callback must be a function" )
local function pack ( ... )
return { n = select ( "#" , ... ) , ... }
end

local function loadLjppModule ( name )
local path = envMod . findRuntimeModulePath ( env , name )
if not path then
return ( "\n\tno nupp source for module '%s'" ) : format ( name )
end

local chunk , loadErr
if path : match ( "%.nupp$" ) then
local code , compileErr = compile ( path , env )
if not code then
error (
(
"error compiling nupp module '%s' from '%s': %s"
) : format ( name , path , compileErr or "compilation failed" ) ,
0
)
end
chunk , loadErr = loadstring ( code , "@" .. path )
else
chunk , loadErr = loadfile ( path )
end
if not chunk then
error ( ( "error loading project module '%s' " .. "from '%s': %s" ) : format ( name , path , tostring ( loadErr ) ) , 0 )
end

if not loaded or not path : match ( "%.nupp$" ) then
return chunk
end





return function ( ... )
local args = { n = select ( "#" , ... ) , ... }
local result
local ok , failure = pcall ( function ( )
result = pack ( chunk ( unpack ( args , 1 , args . n ) ) )
end )
loaded ( name , path , ok )
if not ok then
error ( failure , 0 )
end

return unpack ( result , 1 , result . n )
end
end


table . insert ( loaders , 2 , loadLjppModule )

local installed = true

return function ( )
if not installed then
return
end
installed = false
for j , loader in ipairs ( loaders ) do
if loader == loadLjppModule then
table . remove ( loaders , j )
return
end
end
end
end

return runtime
