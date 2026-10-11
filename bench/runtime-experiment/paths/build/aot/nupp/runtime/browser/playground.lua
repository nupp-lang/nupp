_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()






local json = require ( "nupp.runtime.provider.lunajson" )
local utf8 = require ( "nupp.text.utf8" )

local derive = require ( "nupp.derive" )
local serde = require ( "nupp.serde" )
local dataJson = require ( "nupp.serde.json" )
local document = require ( "nupp.serde.document" )
local nativeValues = require ( "nupp.serde.native" )
local adapters = require ( "nupp.serde.adapters" )
local codecs = require ( "nupp.serde.codec" )
local rendering = require ( "nupp.serde.debug" )


local pegRuntime = require ( "nupp.compiler.runtime.peg" )


local platformLibraries = {
function ( ) 
return require ( "nupp.time" )
end ,
function ( ) 
return require ( "nupp.random" )
end ,
function ( ) 
return require ( "nupp.mac" )
end ,
function ( ) 
return require ( "nupp.digest" )
end ,
function ( ) 
return require ( "nupp.io.storage" )
end ,
function ( ) 
return require ( "nupp.util" )
end ,
function ( ) 
return require ( "nupp.io.http" )
end ,
function ( ) 
return require ( "nupp.gpu" )
end ,
function ( ) 
return require ( "nupp.tasks" )
end ,
function ( ) 
return require ( "nupp.workers" )
end ,
}

local lines = { }
local outputBytes = 0
local OUTPUT_LIMIT = 1048576

local function printable ( value ) 
if utf8 . isValid ( value ) then
return value
end
local pieces = { }
local at = 1
while at <= # value do
local codepoint , nextAt = utf8 . decodeAt ( value , at )
pieces [ # pieces + 1 ] = utf8 . encode ( codepoint )
at = nextAt
end

return table . concat ( pieces )
end

_G . print = function ( ... ) 
local values = { }
for index = 1 , select ( "#" , ... ) do
values [ index ] = tostring ( select ( index , ... ) )
end
local line = printable ( table . concat ( values , "\9" ) )
outputBytes = outputBytes + # line + ( # lines > 0 and 1 or 0 )
if outputBytes > 1048576 then
error ( "nupp: playground output exceeded 1048576 bytes" , 0 )
end
lines [ # lines + 1 ] = line
end

_G . __nuppPlaygroundRun = function ( source ) 
if derive == nil
or serde == nil
or dataJson == nil
or document == nil
or nativeValues == nil
or adapters == nil
or codecs == nil
or rendering == nil
then
error ( "nupp: derive runtime did not load" , 0 )
end
if pegRuntime == nil then
error ( "nupp: PEG runtime did not load" , 0 )
end
assert ( # platformLibraries == 10 , "nupp: browser library loaders are missing" )
lines = { }
outputBytes = 0
local chunk , problem = loadstring ( source , "@playground.nupp" )
if chunk == nil then
error ( problem or "generated Lua did not load" , 0 )
end
chunk ( )

return json . encode ( { stdout = table . concat ( lines , "\n" ) , } )
end

local __nuppExportValue= { } ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.playground"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.playground"]=__nuppExports;return __nuppExports