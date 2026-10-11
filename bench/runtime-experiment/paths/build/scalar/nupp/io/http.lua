_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()



































































































local spi = require ( "nupp.spi" )
local target = require ( "nupp.runtime.target" )

local contracts = require ( "nupp.io.http.spi" )
local messages = require ( "nupp.io.http.messages" )

const paths = require ( "nupp.io.path" )
const appPaths = require ( "nupp.io.files.path" )
local __nuppT1;do local __nuppT2,__nuppT3;repeat
const chosen = spi . select ( spi . load ("nupp.io.http.spi.Provider") )
if chosen ~= nil then
do  __nuppT1= chosen ;__nuppT2=true;break end
end
if target . host == "native" then
do  __nuppT1= _G . require ( "nupp.runtime.provider.nativehttp" ) ;__nuppT2=true;break end
end
do  __nuppT1= _G . require ( "nupp.runtime.browser.http" ) ;__nuppT2=true;break end
 until true; end; local provider = __nuppT1
local http = { }









http . Request = messages . Request

http . ReaderBody = messages . ReaderBody

http . FileBody = messages . FileBody







http . newClient = provider . newClient



http . capabilities = provider . capabilities


























function http . reader ( reader , length , contentType ) 
if type ( reader ) ~= "table"
or type ( ( reader ) . read ) ~= "function"
or type ( ( reader ) . close ) ~= "function"
then
error ( "nupp: HTTP reader body needs a reader" , 2 )
end
if length ~= nil then
if type ( length ) ~= "number" or length < 0 or length % 1 ~= 0 then
error ( "nupp: HTTP reader body length must be a nonnegative integer" , 2 )
end
end
if contentType ~= nil and type ( contentType ) ~= "string" then
error ( "nupp: HTTP content type must be a string" , 2 )
end

return ( _G.setmetatable({ reader =  reader ,  length =  length ,  contentType =  contentType }, messages.ReaderBody) )
end











function http . file ( path , contentType ) 
if type ( path ) ~= "string" and not ( ( _G.getmetatable( path )?.__index == require("nupp.io.path").Path ) ) and not appPaths . is ( path ) then
error ( "nupp: HTTP file body needs a path" , 2 )
end
if contentType ~= nil and type ( contentType ) ~= "string" then
error ( "nupp: HTTP content type must be a string" , 2 )
end

return ( _G.setmetatable({ path =  path ,  contentType =  contentType }, http.FileBody) )
end

local __nuppExportValue= http ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.io.http"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.http"]=__nuppExports;return __nuppExports