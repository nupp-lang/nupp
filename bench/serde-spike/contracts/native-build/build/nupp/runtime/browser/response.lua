_G.assert((_G.loadstring or _G.load)("local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,\"math\")or{};rawset(__nupp,\"math\",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)==\"closed file\"then return end;local ok,reason=handle:close();if not ok then error(reason or \"the file could not be closed\",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups[\"nupp:lua.d.nupp#__nuppCloseFile\"]=__nuppCloseFile require(\"nupp.runtime.managed\").install(__nupp,_G);\n","@nupp-prelude"))();local __nupp=_G.nupp or {};_G.nupp=__nupp local __nuppMath=rawget(__nupp,"math")or{};rawset(__nupp,"math",__nuppMath) local function __nuppCloseFile(handle)if io.type(handle)=="closed file"then return end;local ok,reason=handle:close();if not ok then error(reason or "the file could not be closed",0)end end local __nuppCleanups=_G.__nuppCleanupRegistry or {};_G.__nuppCleanupRegistry=__nuppCleanups;__nuppCleanups["nupp:lua.d.nupp#__nuppCloseFile"]=__nuppCloseFile require("nupp.runtime.managed").install(__nupp,_G);local __nuppExports;local __nuppOk,__nuppWhy=pcall(function()


local effects = require ( "nupp.runtime.browser.effects" )
local suspension = require ( "nupp.suspension" )
local response = { }

function response . await ( kind , payload , discard ) 
local answer = suspension . suspend ( "browser " .. kind , function ( resume ) 
return effects . request ( kind , payload , resume , discard )
end )
if type ( answer ) ~= "table" or type ( answer . ok ) ~= "boolean" then
error ( "nupp: browser " .. kind .. " returned an invalid response" , 2 )
end
if not answer . ok then
if type ( answer . error ) ~= "string" then
error ( "nupp: browser " .. kind .. " returned an invalid error response" , 2 )
end
error ( "nupp: browser " .. kind .. " failed: " .. answer . error , 2 )
end

return answer . value
end

local __nuppExportValue= response ;__nuppExports=__nuppExportValue
 end);if not __nuppOk then package.loaded["nupp.runtime.browser.response"]=nil;error(__nuppWhy,0) end;package.loaded["nupp.runtime.browser.response"]=__nuppExports;return __nuppExports