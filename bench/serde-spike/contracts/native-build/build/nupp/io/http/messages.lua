_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G); require("nupp.compiler.runtime.typewitness").install(__nupp);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()

local __nuppT1={ _G.nupp.__reflect.declaration("nupp.io.http.messages\0runtime\0001") , _G.nupp.__reflect.declaration("nupp.io.http.messages\0runtime\0002") , _G.nupp.__reflect.declaration("nupp.io.http.messages\0runtime\0003") , _G.nupp.__reflect.declaration("nupp.io.http.messages\0runtime\0004") };


const uri = require ( "nupp.io.uri" )
local http = { }


http.Reader = {}







http.Capabilities = {} http.Capabilities.__index = http.Capabilities ;_G.nupp.__reflect.link(http.Capabilities,__nuppT1[1],{ })





















































































http.ReaderBody = {} http.ReaderBody.__index = http.ReaderBody










function http.ReaderBody:close() 
self . reader : close ( )
end ;_G.nupp.__reflect.link(http.ReaderBody,__nuppT1[2],{ _G.nupp.__reflect.reference("../../../../src/nupp/io/http/messages.nupp\0Reader\0interface\0module\0001","nupp.io.http.messages") })






http.FileBody = {} http.FileBody.__index = http.FileBody ;_G.nupp.__reflect.link(http.FileBody,__nuppT1[3],{ _G.nupp.__reflect.reference("../../../../src/nupp/io/files/path.nupp\0ApplicationPath\0interface\0module\0001","nupp.io.files.path") , _G.nupp.__reflect.reference("nupp.io.path\0runtime\0001","nupp.io.path") })



























http.Request = {} http.Request.__index = http.Request



























function http.Request:close() 
if ( _G.getmetatable( self . body )?.__index == http.ReaderBody ) then
self . body : close ( )
end
end ;_G.nupp.__reflect.link(http.Request,__nuppT1[4],{ _G.nupp.__reflect.reference("nupp.io.uri\0runtime\0002","nupp.io.uri") , __nuppT1[2] , __nuppT1[3] })


local __nuppExportValue= http ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.io.http.messages"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.io.http.messages"]=__nuppExports;return __nuppExports